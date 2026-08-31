class Crm::Hubspot::SyncService
  # A private app token cannot subscribe to HubSpot webhooks, so the mirror polls. Each run
  # asks only for deals modified since the last successful sync, which keeps the work
  # proportional to what changed rather than to the size of the CRM.
  OVERLAP = 5.minutes

  def initialize(hook, since: nil)
    @hook = hook
    @since = since
    @processor = Crm::Hubspot::ProcessorService.new(hook)
  end

  def perform
    started_at = Time.current
    imported = 0

    @hook.settings['board_ids'].each_key do |pipeline_id|
      imported += import_pipeline(pipeline_id)
    end

    @hook.settings['last_synced_at'] = started_at.iso8601
    @hook.save!
    imported
  end

  private

  def client
    @client ||= Crm::Hubspot::Api::Client.new(@hook.settings['access_token'])
  end

  # The overlap re-reads a few minutes twice on purpose: a deal changed while a sync was
  # running would otherwise fall between two windows and never be mirrored.
  def since
    @since ||= begin
      last = @hook.settings['last_synced_at']
      last.present? ? Time.zone.parse(last) - OVERLAP : 30.days.ago
    end
  end

  def custom_property_keys
    @custom_property_keys ||= Array(@hook.settings['deal_fields']).pluck('key').compact_blank
  end

  def import_pipeline(pipeline_id)
    deals = client.deals_changed_since(pipeline_id: pipeline_id, since: since, extra_properties: custom_property_keys)
    deals.each { |deal| @processor.process_deal(deal) }
    deals.size
  rescue Crm::Hubspot::Api::Client::ApiError => e
    Rails.logger.error("[HUBSPOT] pipeline #{pipeline_id} failed: #{e.message}")
    0
  end
end
