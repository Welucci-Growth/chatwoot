class Crm::Hubspot::ContactSyncJob < ApplicationJob
  queue_as :low

  # A first import of a large list can outlast the hourly schedule; the lock keeps the next
  # run from importing the same people alongside it and creating them twice.
  LOCK_TIMEOUT = 2.hours

  def perform(hook_id)
    hook = Integrations::Hook.find_by(id: hook_id, app_id: 'hubspot')
    return if hook.blank? || hook.disabled?

    ran = Redis::LockManager.new.with_lock("HUBSPOT_CONTACT_SYNC::#{hook.id}", LOCK_TIMEOUT) do
      counts = Crm::Hubspot::ContactSyncService.new(hook).perform
      Rails.logger.info("[HUBSPOT] hook #{hook.id}: listas espelhadas #{counts}") if counts.present?
    end
    Rails.logger.info("[HUBSPOT] hook #{hook.id}: contact sync already running, skipped") unless ran
  end
end
