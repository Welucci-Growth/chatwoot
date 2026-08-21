# Evolution delivers every instance's events to a single global webhook, so the inbox is
# resolved from the instance name in the payload. Evolution does not sign its payloads, so
# the URL carries a secret shared by all Evolution inboxes on this installation.
class Webhooks::EvolutionController < ActionController::API
  def process_payload
    # The global webhook fans out every Evolution event, and the chatty ones (presence,
    # chat and contact syncs) outnumber messages by orders of magnitude. Dropping them here
    # keeps them from becoming Sidekiq jobs that only get discarded later.
    return head :ok unless Webhooks::EvolutionEventsJob::SUPPORTED_EVENTS.include?(params[:event])

    channel = Channel::Whatsapp.where(provider: 'evolution')
                               .find_by("provider_config->>'instance' = ?", params[:instance])

    # Instances without a mirror inbox are expected — the global webhook receives all of them.
    # Answering ok keeps Evolution from retrying and flooding its logs.
    return head :ok if channel.blank?
    return head :unauthorized unless valid_token?(channel)

    Webhooks::EvolutionEventsJob.perform_later(channel.id, params.to_unsafe_hash)
    head :ok
  end

  private

  def valid_token?(channel)
    expected = channel.provider_config['webhook_verify_token'].to_s
    expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, params[:token].to_s)
  end
end
