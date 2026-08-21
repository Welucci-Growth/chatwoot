# Evolution has no signed payloads, so the webhook is authenticated by a secret embedded in
# the URL. Each Evolution inbox generates its own token when it is created.
class Webhooks::EvolutionController < ActionController::API
  def process_payload
    channel = Channel::Whatsapp.where(provider: 'evolution')
                               .find_by("provider_config->>'webhook_verify_token' = ?", params[:token])

    return head :unauthorized if channel.blank?

    Webhooks::EvolutionEventsJob.perform_later(channel.id, params.to_unsafe_hash)
    head :ok
  end
end
