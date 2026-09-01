# Builds the card panel entirely from what Chatwoot already stores. The Pipedrive panel reads
# the CRM live, but this account asked for no calls to HubSpot, and everything shown here —
# the stage sequence, the linked person — is already on our side.
class Crm::Hubspot::DealPanelService
  def initialize(task)
    @task = task
    @crm = task.custom_attributes['hubspot'] || {}
    @hook = task.account.hooks.find_by!(app_id: 'hubspot')
  end

  def perform
    { stages: stages, contact: contact_summary, person: person }
  end

  private

  # The board columns mirror the pipeline stages in order, so the progress bar is drawn from
  # them rather than from the CRM.
  def stages
    current_column_id = @task.task_column_id

    @task.task_board.task_columns.order(:position).map do |column|
      { name: column.name, current: column.id == current_column_id }
    end
  end

  # The contact behind the card, with the details Chatwoot itself holds.
  def person
    return nil if linked_contact.blank?

    {
      name: linked_contact.name,
      emails: [linked_contact.email.presence].compact,
      phones: [linked_contact.phone_number.presence].compact,
      organization: nil
    }
  end

  def contact_summary
    linked_contact && { id: linked_contact.id, name: linked_contact.name }
  end

  def linked_contact
    return @linked_contact if defined?(@linked_contact)

    @linked_contact = @task.contact || Crm::ContactLinker.link(@task, origin_phones)
  end

  # These deals were migrated from Pipedrive and carry the origin id, which is the only route
  # to the client's phone number that does not call HubSpot.
  def origin_phones
    return [] if origin_person_id.blank? || pipedrive_token.blank?

    person = Crm::Pipedrive::Api::Client.new(pipedrive_token).person(origin_person_id)
    Array(person['phone']).filter_map { |entry| entry['value'].presence }
  end

  def origin_person_id
    deal_id = Array(@crm['fields']).find { |field| field['name'] == 'Pipedrive ID' }&.dig('value')
    return nil if deal_id.blank?

    origin = @task.account.tasks.where("custom_attributes -> 'pipedrive' ->> 'deal_id' = ?", deal_id.to_s).first
    origin&.custom_attributes&.dig('pipedrive', 'person_id')
  end

  def pipedrive_token
    @task.account.hooks.find_by(app_id: 'pipedrive')&.settings&.dig('api_token')
  end
end
