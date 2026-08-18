class Crm::Pipedrive::ProcessorService
  def initialize(hook)
    @hook = hook
    @account = hook.account
  end

  # Handles one Pipedrive webhook event (version 2.0 payload).
  def process(payload)
    data = payload['data']
    return if data.blank?

    action = payload.dig('meta', 'action')

    case payload.dig('meta', 'entity')
    when 'deal' then process_deal(data, action)
    when 'activity' then process_activity(data, action)
    end
  end

  private

  def settings
    @hook.settings
  end

  def client
    @client ||= Crm::Pipedrive::Api::Client.new(settings['api_token'])
  end

  def process_deal(deal, action)
    external_id = "deal-#{deal['id']}"
    board_id = settings.dig('board_ids', deal['pipeline_id'].to_s)
    return discard(external_id) if action == 'delete' || board_id.blank?

    board = @account.task_boards.find(board_id)
    column_id = settings.dig('stage_columns', deal['stage_id'].to_s) || board.task_columns.first.id

    upsert_task(external_id, board, column_id, deal_attributes(deal, external_id))
  end

  def process_activity(activity, action)
    external_id = "activity-#{activity['id']}"
    board_id = settings.dig('board_ids', 'activities')
    return discard(external_id) if action == 'delete' || board_id.blank?

    board = @account.task_boards.find(board_id)
    column = activity['done'] ? board.task_columns.last : board.task_columns.first

    upsert_task(external_id, board, column.id, activity_attributes(activity, external_id))
  end

  def deal_attributes(deal, external_id)
    {
      title: deal['title'].presence || "Negócio #{deal['id']}",
      description: deal_description(deal),
      due_on: parse_date(deal['expected_close_date']),
      assignee_id: settings.dig('user_map', deal['owner_id'].to_s),
      contact_id: contact_for(deal['person_id'])&.id,
      custom_attributes: {
        'pipedrive' => {
          'id' => external_id,
          'type' => 'deal',
          'deal_id' => deal['id'],
          'pipeline_id' => deal['pipeline_id'],
          'stage_id' => deal['stage_id'],
          'person_id' => deal['person_id'],
          'status' => deal['status'],
          'url' => "#{crm_base_url}/deal/#{deal['id']}"
        }
      }
    }
  end

  def activity_attributes(activity, external_id)
    {
      title: activity['subject'].presence || "Atividade #{activity['id']}",
      description: strip_html(activity['note']),
      due_on: parse_datetime(activity['due_date'], activity['due_time']),
      assignee_id: settings.dig('user_map', activity['owner_id'].to_s),
      contact_id: contact_for(activity['person_id'])&.id,
      custom_attributes: {
        'pipedrive' => {
          'id' => external_id,
          'type' => 'activity',
          'activity_id' => activity['id'],
          'activity_type' => activity['type'],
          'deal_id' => activity['deal_id'],
          'person_id' => activity['person_id'],
          'done' => activity['done'],
          'url' => "#{crm_base_url}/activities/list/user/everyone/activity/#{activity['id']}"
        }
      }
    }
  end

  def deal_description(deal)
    [
      deal['value'].present? ? "Valor: #{deal['currency']} #{deal['value']}" : nil,
      deal['status'].present? ? "Status: #{deal['status']}" : nil
    ].compact.join("\n").presence
  end

  def upsert_task(external_id, board, column_id, attributes)
    task = find_task(external_id)

    if task.present?
      task.update!(attributes.merge(task_board_id: board.id, task_column_id: column_id))
    else
      board.tasks.create!(attributes.merge(task_column_id: column_id))
    end
  end

  def discard(external_id)
    find_task(external_id)&.destroy!
  end

  def find_task(external_id)
    @account.tasks.with_external_reference('pipedrive', external_id).first
  end

  # Links the card to the Chatwoot contact, caching the Pipedrive id on the contact so
  # later events skip the API call.
  def contact_for(person_id)
    return nil if person_id.blank?

    @contacts_by_person_id ||= {}
    return @contacts_by_person_id[person_id] if @contacts_by_person_id.key?(person_id)

    @contacts_by_person_id[person_id] = resolve_contact(person_id)
  end

  def resolve_contact(person_id)
    cached = @account.contacts.where("contacts.additional_attributes -> 'external' ->> 'pipedrive_id' = ?", person_id.to_s).first
    return cached if cached.present?

    contact = match_contact(client.person(person_id))
    return nil if contact.blank?

    contact.additional_attributes = contact.additional_attributes.deep_merge('external' => { 'pipedrive_id' => person_id.to_s })
    contact.save!
    contact
  end

  def match_contact(person)
    emails = Array(person['email']).filter_map { |entry| entry['value'].presence&.downcase }
    phones = Array(person['phone']).filter_map { |entry| entry['value'].presence }

    @account.contacts.where(email: emails).first || @account.contacts.where(phone_number: phones).first
  end

  def crm_base_url
    "https://#{settings['company_domain']}.pipedrive.com"
  end

  def parse_date(value)
    value.present? ? Time.zone.parse(value) : nil
  end

  def parse_datetime(date, time)
    return nil if date.blank?

    Time.zone.parse([date, time].compact_blank.join(' '))
  end

  def strip_html(value)
    return nil if value.blank?

    ActionView::Base.full_sanitizer.sanitize(value.gsub(%r{<br\s*/?>}i, "\n")).strip.presence
  end
end
