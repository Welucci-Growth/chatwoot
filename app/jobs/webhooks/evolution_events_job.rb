class Webhooks::EvolutionEventsJob < MutexApplicationJob
  queue_as :low
  # Mirrors the WhatsApp job: the retry budget (19 x 2s) has to outlast the 30s lock TTL so a
  # webhook arriving right after the lock is taken cannot exhaust its retries and vanish.
  retry_on LockAcquisitionError, wait: 2.seconds, attempts: 20

  SUPPORTED_EVENTS = ['messages.upsert'].freeze

  def perform(channel_id, payload = {})
    params = payload.with_indifferent_access
    return unless SUPPORTED_EVENTS.include?(params[:event])

    channel = Channel::Whatsapp.find(channel_id)
    return unless channel.account.active?

    # Media albums arrive as concurrent webhooks; serialize per (inbox, chat) so the first one
    # creates the conversation and the rest append to it.
    key = format(::Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: sender_id(params))
    with_lock(key, 30.seconds) do
      Whatsapp::IncomingMessageEvolutionService.new(
        inbox: channel.inbox,
        params: params,
        outgoing_echo: params.dig(:data, :key, :fromMe).present?
      ).perform
    end
  end

  private

  def sender_id(params)
    params.dig(:data, :key, :remoteJid)
  end
end
