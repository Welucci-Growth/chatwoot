class Webhooks::PipedriveController < ActionController::API
  include ActionController::HttpAuthentication::Basic::ControllerMethods

  def process_payload
    return head :not_found if hook.blank?
    return head :unauthorized unless authenticated?

    Webhooks::PipedriveEventsJob.perform_later(hook.id, params.to_unsafe_hash.slice('meta', 'data'))
    head :ok
  end

  private

  def hook
    @hook ||= Integrations::Hook.find_by(id: params[:hook_id], app_id: 'pipedrive')
  end

  # Pipedrive signs the callback with the basic auth credentials we set when subscribing.
  def authenticated?
    secret = hook.settings['webhook_secret']
    return false if secret.blank?

    authenticate_with_http_basic { |_user, password| ActiveSupport::SecurityUtils.secure_compare(password.to_s, secret) }
  end
end
