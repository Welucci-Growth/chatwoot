class Webhooks::HubspotEventsJob < ApplicationJob
  queue_as :low

  # HubSpot sends what changed, not the record itself, so each event is resolved back to the
  # deal through the same processor the scheduled sync uses.
  def perform(hook_id, events)
    hook = Integrations::Hook.find_by(id: hook_id)
    return if hook.blank? || hook.disabled?

    client = Crm::Hubspot::Api::Client.new(hook.settings['access_token'])
    processor = Crm::Hubspot::ProcessorService.new(hook)

    deal_ids(events).each do |deal_id|
      processor.process_deal(client.deal(deal_id))
    rescue Crm::Hubspot::Api::Client::ApiError => e
      Rails.logger.error("[HUBSPOT] deal #{deal_id} failed: #{e.message}")
    end
  end

  private

  # A single change can arrive as several property events; mirroring the deal once is enough.
  def deal_ids(events)
    Array(events).filter_map do |event|
      event['objectId'] if event['subscriptionType'].to_s.start_with?('deal.')
    end.uniq
  end
end
