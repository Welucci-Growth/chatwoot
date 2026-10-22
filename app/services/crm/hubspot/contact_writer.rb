# Writes HubSpot people into Chatwoot contacts without firing contact events. An import touches
# thousands of contacts at once, and each event reaches the account webhooks and automations:
# a flow that greets new contacts would message every customer in the CRM.
#
# Records still go through the model's own validations and attribute sync before being written.
class Crm::Hubspot::ContactWriter
  LOOKUP_SLICE = 1000

  def initialize(hook, fields:)
    @hook = hook
    @account = hook.account
    @fields = fields
    @processor = Crm::Hubspot::ProcessorService.new(hook)
  end

  # Returns { hubspot_id => contact_id } for everyone it could place. People without a phone
  # are only linked when they already exist: a contact Chatwoot cannot reach is not created.
  def write(people)
    linked = linked_contacts(people.map { |person| person['id'].to_s })
    pending = []

    placed = people.each_with_object({}) do |person, index|
      hubspot_id = person['id'].to_s
      attributes = attributes_from(person)
      contact = linked[hubspot_id] || @processor.match_contact(person)

      if contact
        index[hubspot_id] = contact.id if update_quietly(contact, hubspot_id, attributes)
      elsif attributes[:phone_number].present?
        pending << [hubspot_id, attributes]
      end
    end

    placed.merge(insert_quietly(pending))
  end

  # { hubspot_id => contact } for the people already linked, found without asking HubSpot.
  def linked_contacts(hubspot_ids)
    hubspot_ids.each_slice(LOOKUP_SLICE).with_object({}) do |slice, index|
      @account.contacts
              .where("contacts.additional_attributes -> 'external' ->> 'hubspot_id' IN (?)", slice)
              .find_each { |contact| index[contact.additional_attributes.dig('external', 'hubspot_id')] = contact }
    end
  end

  private

  def attributes_from(person)
    props = person['properties'] || {}
    email = props['email'].to_s.strip.downcase.presence

    {
      name: props.values_at('firstname', 'lastname').map { |part| part.to_s.strip }.compact_blank.join(' ').presence,
      email: email&.match?(Devise.email_regexp) ? email : nil,
      phone_number: @processor.phone_values(props).lazy.filter_map { |value| Crm::ContactMatcher.normalize_phone(value) }.first,
      city: props['city'].presence,
      company: props['company'].presence,
      custom_attributes: @fields.custom_attributes_for(props)
    }
  end

  # Chatwoot's own data wins for name, email and phone: a number that came in through WhatsApp
  # is the one known to work, so HubSpot only fills what is missing. The HubSpot fields are
  # always refreshed, since that is where they are kept.
  def update_quietly(contact, hubspot_id, attributes)
    contact.additional_attributes = contact.additional_attributes.deep_merge('external' => { 'hubspot_id' => hubspot_id })
    contact.custom_attributes = contact.custom_attributes.merge(attributes[:custom_attributes])
    fill_blanks(contact, attributes)
    return true unless contact.changed?

    persist_quietly(contact)
  end

  def fill_blanks(contact, attributes)
    contact.name = attributes[:name] if attributes[:name].present? && placeholder_name?(contact)
    %i[email phone_number].each do |field|
      contact[field] = attributes[field] if contact[field].blank? && available?(field, attributes[field])
    end
    from_hubspot = { 'city' => attributes[:city], 'company_name' => attributes[:company] }.compact
    contact.additional_attributes = from_hubspot.merge(contact.additional_attributes)
  end

  def persist_quietly(contact)
    Contacts::SyncAttributes.new(contact).perform
    unless contact.valid?
      Rails.logger.error("[HUBSPOT] contact #{contact.id} not updated: #{contact.errors.full_messages.to_sentence}")
      return false
    end

    contact.update_columns(contact.changes_to_save.transform_values(&:last).merge('updated_at' => Time.current)) # rubocop:disable Rails/SkipsModelValidations
    true
  end

  # Two people in the same batch can share a phone or an email; the first one keeps it.
  def insert_quietly(pending)
    seen = Set.new
    rows = pending.filter_map do |hubspot_id, attributes|
      next if [attributes[:phone_number], attributes[:email]].compact.any? { |value| seen.include?(value) }

      seen.merge([attributes[:phone_number], attributes[:email]].compact)
      new_contact_row(hubspot_id, attributes)
    end
    return {} if rows.empty?

    Contact.insert_all(rows) # rubocop:disable Rails/SkipsModelValidations
    linked_contacts(pending.map(&:first)).transform_values(&:id)
  end

  def new_contact_row(hubspot_id, attributes)
    contact = @account.contacts.new(
      name: attributes[:name] || attributes[:phone_number],
      email: attributes[:email],
      phone_number: attributes[:phone_number],
      custom_attributes: attributes[:custom_attributes],
      additional_attributes: { 'external' => { 'hubspot_id' => hubspot_id },
                               'city' => attributes[:city], 'company_name' => attributes[:company] }.compact
    )
    Contacts::SyncAttributes.new(contact).perform
    return log_skip(hubspot_id, contact) unless contact.valid?

    now = Time.current
    contact.attributes.slice(*Contact.column_names).except('id').merge('created_at' => now, 'updated_at' => now)
  end

  def log_skip(hubspot_id, contact)
    Rails.logger.error("[HUBSPOT] contact #{hubspot_id} not imported: #{contact.errors.full_messages.to_sentence}")
    nil
  end

  # WhatsApp names a contact after its number when the profile has no name.
  def placeholder_name?(contact)
    contact.name.blank? || contact.name.gsub(/\D/, '') == contact.phone_number.to_s.delete('+')
  end

  def available?(field, value)
    value.present? && !@account.contacts.exists?(field => value)
  end
end
