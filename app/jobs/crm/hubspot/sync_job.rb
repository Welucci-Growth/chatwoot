class Crm::Hubspot::SyncJob < ApplicationJob
  queue_as :low

  def perform(hook_id = nil, since: nil)
    hooks(hook_id).each do |hook|
      count = Crm::Hubspot::SyncService.new(hook, since: since).perform
      Rails.logger.info("[HUBSPOT] hook #{hook.id}: #{count} negócios espelhados")
    rescue StandardError => e
      Rails.logger.error("[HUBSPOT] hook #{hook.id} failed: #{e.message}")
    end
  end

  private

  def hooks(hook_id)
    return Integrations::Hook.where(id: hook_id) if hook_id.present?

    Integrations::Hook.where(app_id: 'hubspot', status: 'enabled')
  end
end
