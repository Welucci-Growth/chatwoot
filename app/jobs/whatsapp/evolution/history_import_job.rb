# Imports a newly connected number's recent history, then turns its live mirror on.
#
# The inbox is created paused, so the window is imported first and every live message lands
# after it; a second pass then picks up what arrived while the first one ran. Nothing here
# dispatches events: these messages were already seen in WhatsApp, and replaying them would
# fire webhooks, automations and notifications for old news.
class Whatsapp::Evolution::HistoryImportJob < ApplicationJob
  queue_as :low

  CATCH_UP_OVERLAP = 5.minutes

  def perform(inbox_id, days = 30)
    inbox = Inbox.find(inbox_id)
    started_at = Time.current

    Dispatcher.silently do
      imported = Whatsapp::Evolution::HistoryImportService.new(inbox: inbox, since: days.days.ago).perform
      inbox.channel.update!(provider_config: inbox.channel.provider_config.except('mirror_paused'))
      caught_up = Whatsapp::Evolution::HistoryImportService.new(inbox: inbox, since: started_at - CATCH_UP_OVERLAP).perform
      Rails.logger.info("[EVOLUTION_HISTORY] inbox #{inbox.id}: #{imported} mensagens importadas, #{caught_up} na repassada")
    end
  end
end
