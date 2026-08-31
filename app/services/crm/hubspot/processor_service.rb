class Crm::Hubspot::ProcessorService
  SOURCE = 'hubspot'.freeze

  def initialize(hook, contact_index: nil)
    @hook = hook
    @account = hook.account
    # Resolved in bulk by the caller when importing many deals, so the processor never
    # issues one API call per card.
    @contact_index = contact_index
  end

  # Turns one HubSpot deal into the card that mirrors it. Running twice updates the card
  # rather than duplicating it, which is what makes the scheduled sync safe to repeat.
  def process_deal(deal)
    props = deal['properties'] || {}
    external_id = "deal-#{deal['id']}"
    board_id = settings.dig('board_ids', props['pipeline'].to_s)
    return if board_id.blank?

    board = @account.task_boards.find(board_id)
    column_id = settings.dig('stage_columns', props['dealstage'].to_s) || board.task_columns.first.id

    upsert_task(external_id, board, column_id, deal_attributes(deal, props, external_id))
  end

  # Public so the bulk sync reuses the same matching rules instead of copying them.
  # Caches the HubSpot id on the Chatwoot contact so later runs match without a lookup.
  def link_contact(hubspot_id, person)
    cached = @account.contacts.where("contacts.additional_attributes -> 'external' ->> 'hubspot_id' = ?", hubspot_id.to_s).first
    return cached if cached.present?
    return nil if person.blank?

    contact = match_contact(person)
    return nil if contact.blank?

    contact.additional_attributes = contact.additional_attributes.deep_merge('external' => { 'hubspot_id' => hubspot_id.to_s })
    contact.save!
    contact
  end

  def match_contact(person)
    props = person['properties'] || {}
    email = props['email'].to_s.downcase.presence
    phone = props['phone'].presence

    (email && @account.contacts.from_email(email)) || (phone && @account.contacts.find_by(phone_number: phone))
  end

  private

  def settings
    @hook.settings
  end

  def client
    @client ||= Crm::Hubspot::Api::Client.new(settings['access_token'])
  end

  def deal_attributes(deal, props, external_id)
    {
      title: props['dealname'].presence || "Negócio #{deal['id']}",
      description: description_for(props),
      due_on: parse_time(props['closedate']),
      assignee_id: settings.dig('owner_map', props['hubspot_owner_id'].to_s),
      contact_id: contact_for(deal['id'])&.id,
      custom_attributes: { SOURCE => snapshot(deal, props, external_id) }
    }
  end

  def snapshot(deal, props, external_id)
    {
      'id' => external_id,
      'type' => 'deal',
      'deal_id' => deal['id'],
      'pipeline_id' => props['pipeline'],
      'stage_id' => props['dealstage'],
      'owner_id' => props['hubspot_owner_id'],
      'deal_type' => props['dealtype'],
      'closed_won' => props['hs_is_closed_won'],
      'lost_reason' => props['closed_lost_reason'],
      'close_date' => props['closedate'],
      'added_at' => props['createdate'],
      'updated_at' => props['hs_lastmodifieddate'],
      'amounts' => { 'value' => props['amount'] }.compact_blank,
      'fields' => filled_fields(props),
      'url' => deal_url(deal['id'])
    }.compact
  end

  def description_for(props)
    [
      props['amount'].present? ? "Valor: #{props['amount']}" : nil,
      props['dealtype'].presence,
      props['description'].presence
    ].compact_blank.join("\n").presence
  end

  # Most custom properties are empty on any given deal, so the card only carries the ones
  # that are filled, labelled and ordered as they are in the CRM.
  def filled_fields(props)
    Array(settings['deal_fields']).sort_by { |field| field['order'].to_i }.filter_map do |field|
      value = props[field['key']]
      next if value.blank?

      { 'name' => field['name'], 'value' => field.dig('options', value.to_s) || value.to_s }
    end
  end

  def upsert_task(external_id, board, column_id, attributes)
    task = find_task(external_id)

    if task.present?
      task.update!(attributes.merge(task_board_id: board.id, task_column_id: column_id))
    else
      board.tasks.create!(attributes.merge(task_column_id: column_id))
    end
  end

  def find_task(external_id)
    @account.tasks.with_external_reference(SOURCE, external_id).first
  end

  # Links the card to the Chatwoot contact, caching the HubSpot id on the contact so
  # later syncs skip the API calls.
  def contact_for(deal_id)
    return @contact_index[deal_id.to_s] if @contact_index.present?

    @contacts_by_deal ||= {}
    @contacts_by_deal[deal_id] ||= resolve_single(deal_id)
  end

  # Used by the webhook path, where a single deal arrives on its own and batching would
  # not save anything.
  def resolve_single(deal_id)
    hubspot_id = client.deal_contact_ids([deal_id])[deal_id.to_s]
    return nil if hubspot_id.blank?

    link_contact(hubspot_id, client.contacts([hubspot_id])[hubspot_id.to_s])
  rescue Crm::Hubspot::Api::Client::ApiError
    nil
  end

  def deal_url(deal_id)
    portal = settings['portal_id'].presence
    portal ? "https://app.hubspot.com/contacts/#{portal}/deal/#{deal_id}" : nil
  end

  def parse_time(value)
    value.present? ? Time.zone.parse(value.to_s) : nil
  rescue ArgumentError
    nil
  end
end
