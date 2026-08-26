# Evolution takes up to 40 seconds to list one instance's groups, so the dashboard never waits
# on it: this job fills the cache and the panel polls until the data shows up.
class Whatsapp::Evolution::GroupSyncJob < ApplicationJob
  queue_as :low

  def perform(instance)
    Whatsapp::Evolution::GroupService.new.sync_groups(instance)
  rescue StandardError => e
    Rails.logger.error("[EVOLUTION_GROUPS] sync failed for #{instance}: #{e.message}")
  end
end
