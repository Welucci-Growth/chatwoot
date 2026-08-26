# Closes password authentication for Welucci addresses once the Hub is the only door.
#
# The same shape of guard the upstream applies to SAML users, and inert until
# WELUCCI_HUB_ENFORCE_SSO is on — which is what makes turning that flag back off a complete
# rollback. Addresses outside the Welucci domain keep their password login untouched.
module WelucciHubSsoConcern
  private

  def block_password_login_for_hub_users
    return unless Welucci::Hub.enforced_email?(params[:email])
    # `process_sso_auth_token` sets @resource only for a token it has already validated, so
    # this is the Hub-blessed path arriving — let it through. The MFA step carries no email
    # at all, so it never reaches here.
    return if @resource.present? && params[:sso_auth_token].present?

    render json: {
      success: false,
      message: I18n.t('messages.login_welucci_hub_user'),
      errors: [I18n.t('messages.login_welucci_hub_user')]
    }, status: :unauthorized
  end
end
