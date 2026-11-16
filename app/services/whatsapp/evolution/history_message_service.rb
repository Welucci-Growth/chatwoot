# Recreates one message from an Evolution history record through the same pipeline the live
# mirror uses, keeping the time it was sent instead of the time it was imported.
class Whatsapp::Evolution::HistoryMessageService < Whatsapp::IncomingMessageEvolutionService
  private

  def sent_at
    @sent_at ||= Time.zone.at(data[:messageTimestamp].to_i)
  end

  def create_message(...)
    super.tap { |message| message.created_at = message.updated_at = sent_at }
  end

  def conversation_params
    super.merge(created_at: sent_at)
  end

  # The live mirror asks Evolution for the subject on every group message; the directory
  # already has it, and an import touches thousands of messages.
  def group_name
    WhatsappGroup.find_by(account_id: inbox.account_id, jid: remote_jid)&.subject.presence || super
  end
end
