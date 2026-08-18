class Crm::Pipedrive::BackfillService
  def initialize(hook, updated_since:)
    @hook = hook
    @updated_since = updated_since
    @processor = Crm::Pipedrive::ProcessorService.new(hook)
  end

  # Pulls everything changed in the CRM since a given moment through the same path the
  # webhooks use, so running it twice updates the cards instead of duplicating them.
  def perform
    imported = { 'deals' => 0, 'activities' => 0 }

    @hook.settings['board_ids'].each_key do |key|
      imported['activities'] += import_activities if key == 'activities'
      imported['deals'] += import_deals(key) unless key == 'activities'
    end

    imported
  end

  private

  def client
    @client ||= Crm::Pipedrive::Api::Client.new(@hook.settings['api_token'])
  end

  def import_deals(pipeline_id)
    deals = client.deals(pipeline_id: pipeline_id, updated_since: @updated_since)
    deals.each { |deal| process('deal', deal) }
    deals.size
  end

  def import_activities
    activities = client.activities(updated_since: @updated_since)
    activities.each { |activity| process('activity', activity) }
    activities.size
  end

  def process(entity, record)
    @processor.process('meta' => { 'entity' => entity, 'action' => 'change' }, 'data' => record.stringify_keys)
  end
end
