class Webhooks::PipedriveEventsJob < ApplicationJob
  queue_as :default

  def perform(hook_id, payload)
    hook = Integrations::Hook.find_by(id: hook_id, app_id: 'pipedrive')
    return if hook.blank? || hook.disabled?

    Crm::Pipedrive::ProcessorService.new(hook).process(payload)
  end
end
