# The Welucci Hub (weHub) is the identity provider for every Welucci app: a person signs in
# there once and each app receives them through a single-use token that the Hub mints and
# redeems. This module holds the Hub-facing configuration and that redemption call, so the
# controller stays free of transport concerns.
#
# Nothing here is reachable unless the installation is configured for it — see `configured?`.
# On an unconfigured installation (a dev machine, for one) Chatwoot behaves exactly as it
# did before this shipped.
module Welucci::Hub
  DEFAULT_EMAIL_DOMAIN = 'welucci.com'.freeze
  DEFAULT_PLATFORM_ID = 'chatwoot'.freeze
  TIMEOUT_SECONDS = 8

  class << self
    # Internal (server-to-server) base URL of the Hub. Only this process talks to it.
    def api_url
      ENV.fetch('WELUCCI_HUB_API_URL', '').to_s.strip.chomp('/').presence
    end

    # Public base URL the browser is sent to for the login hand-off. Falls back to the
    # internal one, which is the same host on this installation.
    def public_url
      (ENV.fetch('WELUCCI_HUB_PUBLIC_URL', nil).presence || api_url).to_s.strip.chomp('/').presence
    end

    # Shared secret behind the Hub's `/api/internal/*` endpoints.
    def internal_secret
      ENV.fetch('WELUCCI_HUB_INTERNAL_SECRET', '').to_s.presence
    end

    # The id Chatwoot is registered under in the Hub's platform registry. The Hub scopes
    # each token to one platform, so this has to match on both sides.
    def platform_id
      ENV.fetch('WELUCCI_HUB_PLATFORM_ID', DEFAULT_PLATFORM_ID).to_s.strip.presence || DEFAULT_PLATFORM_ID
    end

    def email_domain
      ENV.fetch('WELUCCI_HUB_EMAIL_DOMAIN', DEFAULT_EMAIL_DOMAIN).to_s.strip.downcase.delete_prefix('@')
    end

    # Which Chatwoot account SSO arrivals are provisioned into. Explicit on purpose:
    # inferring it (`Account.first`) would quietly put people in the wrong account the day
    # a second one exists.
    def account_id
      ENV.fetch('WELUCCI_HUB_ACCOUNT_ID', '').to_s.strip.presence
    end

    # SSO is wired up only when we know where the Hub is, how to authenticate to it, and
    # which account to land people in.
    def configured?
      api_url.present? && internal_secret.present? && account_id.present?
    end

    # Entry point for the button on Chatwoot's login page. `/apps` mints a token straight
    # away when there is already a Hub session, and bounces through the Hub login screen
    # when there is not — the same round trip every other Welucci app uses.
    def login_url
      "#{public_url}/apps?return_platform=#{platform_id}" if configured?
    end

    # Whether password authentication is closed for Welucci accounts, making the Hub the
    # only door. Behind its own flag so that turning it off is a one-variable rollback if
    # the Hub is ever unreachable.
    def enforce_sso?
      configured? && ActiveModel::Type::Boolean.new.cast(ENV.fetch('WELUCCI_HUB_ENFORCE_SSO', false))
    end

    # True when this address must come in through the Hub. Addresses outside the Welucci
    # domain — integration users, external collaborators — keep their password login.
    def enforced_email?(email)
      return false unless enforce_sso?
      return false if email.blank?

      email.to_s.strip.downcase.end_with?("@#{email_domain}")
    end

    # Redeems a single-use token at the Hub and returns the identity behind it, or nil.
    #
    # The Hub deletes the token as it reads it, so a replay of the same token comes back
    # invalid. An unreachable Hub is a real production path — it restarts on deploy — and
    # the answer to it is the same as to a bad token: send the person back to the login
    # screen. So both collapse to nil here rather than to an exception.
    def verify_sso_token(token)
      response = HTTParty.post(
        "#{api_url}/api/internal/verify-sso-token",
        headers: {
          'Content-Type' => 'application/json',
          'X-Internal-Secret' => internal_secret
        },
        body: { token: token, platform: platform_id }.to_json,
        timeout: TIMEOUT_SECONDS
      )
      payload = response.parsed_response
      # The Hash check is not ceremony: a proxy error page would come back as a String, and
      # `'...'['success']` is substring matching, which would read as a valid identity.
      return nil unless response.success? && payload.is_a?(Hash) && payload['success']

      payload
    rescue StandardError => e
      Rails.logger.error("[welucci-hub] SSO token verification failed: #{e.message}")
      nil
    end
  end
end
