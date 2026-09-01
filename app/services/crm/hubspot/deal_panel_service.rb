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
    { stages: stages, person: person }
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

  # The contact linked at mirror time, with the details Chatwoot itself holds.
  def person
    contact = @task.contact
    return nil if contact.blank?

    {
      name: contact.name,
      emails: [contact.email.presence].compact,
      phones: [contact.phone_number.presence].compact,
      organization: nil
    }
  end
end
