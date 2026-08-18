class Crm::Pipedrive::BackfillJob < ApplicationJob
  queue_as :low

  def perform(hook_id, updated_since)
    hook = Integrations::Hook.find_by(id: hook_id, app_id: 'pipedrive')
    return if hook.blank? || hook.disabled?

    imported = Crm::Pipedrive::BackfillService.new(hook, updated_since: updated_since).perform
    Rails.logger.info "Pipedrive backfill for hook ##{hook_id} since #{updated_since}: #{imported}"
  end
end
