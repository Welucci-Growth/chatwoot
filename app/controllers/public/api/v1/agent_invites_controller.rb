class Public::Api::V1::AgentInvitesController < PublicController
  ALLOWED_DOMAIN = '@welucci.com'.freeze

  before_action :fetch_invite

  def show
    render json: {
      account_name: @invite.account.name,
      team_name: @invite.team&.name,
      role: @invite.role,
      allowed_domain: ALLOWED_DOMAIN
    }
  end

  def accept
    email = params[:email].to_s.downcase.strip
    unless email.end_with?(ALLOWED_DOMAIN)
      return render json: { error: "O e-mail precisa terminar com #{ALLOWED_DOMAIN}" }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      user = find_or_create_user(email)
      link_to_account(user)
      link_to_team(user)
    end
    render json: { success: true }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  private

  def fetch_invite
    @invite = AgentInvite.active.find_by!(token: params[:token])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Convite inválido ou expirado' }, status: :not_found
  end

  def find_or_create_user(email)
    existing = User.from_email(email)
    return existing if existing

    user = User.new(
      name: params[:name].presence || email.split('@').first,
      email: email,
      password: params[:password],
      password_confirmation: params[:password]
    )
    user.skip_confirmation!
    user.save!
    user
  end

  def link_to_account(user)
    return if @invite.account.account_users.exists?(user_id: user.id)

    AccountUser.create!(
      account: @invite.account,
      user: user,
      role: @invite.role,
      inviter: @invite.inviter
    )
  end

  def link_to_team(user)
    return if @invite.team_id.blank?
    return if TeamMember.exists?(team_id: @invite.team_id, user_id: user.id)

    TeamMember.create!(team_id: @invite.team_id, user_id: user.id)
  end
end
