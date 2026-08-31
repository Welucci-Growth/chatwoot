class Internal::TriggerHourlyScheduledItemsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Channels::Whatsapp::HealthSyncSchedulerJob.perform_later
    Whatsapp::Evolution::GroupRefreshJob.perform_later
    Crm::Hubspot::SyncJob.perform_later
  end
end

Internal::TriggerHourlyScheduledItemsJob.prepend_mod_with('Internal::TriggerHourlyScheduledItemsJob')
