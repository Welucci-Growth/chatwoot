# Landing point for the Hub's SSO redirect: `${FRONTEND_URL}/sso?token=...`.
#
# Every Welucci app exposes this same path, so the Hub needs no special case for Chatwoot.
# The token is redeemed server-to-server and then handed to Chatwoot's *own* single-use
# `sso_auth_token` login — the mechanism super admins already use to sign in as a user.
# That is what keeps this additive: Devise, MFA and the password form are untouched, and
# dropping this route restores the previous behaviour exactly.
class Welucci::SsoController < PublicController
  def show
    return redirect_to_login('sso-unavailable') unless Welucci::Hub.configured?

    identity = Welucci::Hub.verify_sso_token(params[:token].to_s)
    return redirect_to_login('sso-failed') if identity.blank?

    user = Welucci::SsoProvisioningService.new(email: identity['email'], name: identity['username']).perform

    # `generate_sso_link` mints a token that lives 5 minutes in Redis and dies on first use,
    # and points at the login screen, which auto-submits when it sees one.
    redirect_to user.generate_sso_link, allow_other_host: true
  end

  private

  def redirect_to_login(error)
    redirect_to "#{ENV.fetch('FRONTEND_URL', '')}/app/login?error=#{error}", allow_other_host: true
  end
end
