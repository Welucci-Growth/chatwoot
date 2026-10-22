# Brings the HubSpot contacts that have a phone into Chatwoot, with the properties the team
# segments by, so they can be filtered, saved as segments and picked as a campaign audience.
#
# The first run walks the whole CRM and saves its cursor after every page, so an import cut
# short by a deploy resumes where it stopped. Later runs only read what changed since.
# Reads from HubSpot only and never sends a message.
class Crm::Hubspot::ContactImportService
  # A contact changed while a run was reading would otherwise fall between two windows.
  OVERLAP = 5.minutes

  def initialize(hook)
    @hook = hook
  end

  def perform
    fields = Crm::Hubspot::ContactFields.new(@hook.account, client).sync_definitions!
    @writer = Crm::Hubspot::ContactWriter.new(@hook, fields: fields)
    @properties = (Crm::Hubspot::Api::Client::CONTACT_PROPERTIES + fields.properties).uniq

    state['completed_at'].present? ? import_changes : import_everything
  end

  private

  def state
    @state ||= (@hook.settings['contacts_import'] || {}).dup
  end

  def client
    @client ||= Crm::Hubspot::Api::Client.new(@hook.settings['access_token'])
  end

  def import_everything
    state['started_at'] ||= Time.current.iso8601
    imported = 0

    loop do
      people, state['cursor'] = client.contacts_page(after: state['cursor'], properties: @properties)
      imported += @writer.write(people).size
      save_state
      break if state['cursor'].blank?
    end

    finish(state['started_at'])
    imported
  end

  def import_changes
    started_at = Time.current.iso8601
    imported = 0

    client.each_contact_changed_since(Time.zone.parse(state['completed_at']) - OVERLAP, properties: @properties) do |people|
      people.each_slice(Crm::Hubspot::Api::Client::BATCH_SIZE) { |batch| imported += @writer.write(batch).size }
    end

    finish(started_at)
    imported
  end

  def finish(completed_at)
    @state = { 'completed_at' => completed_at }
    save_state
  end

  def save_state
    @hook.merge_settings!('contacts_import' => state)
  end
end
