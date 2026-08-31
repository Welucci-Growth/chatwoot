# HubSpot delivers events as an array, signed with the app's client secret. Signature
# verification only runs when the secret is configured, so a mirror can be brought up
# before the developer app credentials are in hand.
class Webhooks::HubspotController < ActionController::API
  def process_payload
    hook = Integrations::Hook.find_by(id: params[:hook_id], app_id: 'hubspot')
    return head :not_found if hook.blank?
    return head :unauthorized unless valid_signature?(hook)

    ::Webhooks::HubspotEventsJob.perform_later(hook.id, events)
    head :ok
  end

  private

  def events
    payload = params[:_json].presence || params[:events].presence || []
    Array(payload).map(&:to_unsafe_h)
  end

  def valid_signature?(hook)
    secret = hook.settings['client_secret']
    return true if secret.blank?

    signature = request.headers['X-HubSpot-Signature-v3']
    timestamp = request.headers['X-HubSpot-Request-Timestamp']
    return false if signature.blank? || timestamp.blank? || stale?(timestamp)

    ActiveSupport::SecurityUtils.secure_compare(expected_signature(secret, timestamp), signature)
  end

  # HubSpot requires rejecting anything older than five minutes, so a captured delivery
  # cannot be replayed later.
  def stale?(timestamp)
    ((Time.current.to_i * 1000) - timestamp.to_i).abs > 5.minutes.in_milliseconds
  end

  def expected_signature(secret, timestamp)
    payload = "POST#{request.original_url}#{request.raw_post}#{timestamp}"
    Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', secret, payload))
  end
end
