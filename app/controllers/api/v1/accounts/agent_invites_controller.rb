class Api::V1::Accounts::AgentInvitesController < Api::V1::Accounts::BaseController
  before_action :fetch_invite, only: [:destroy]
  before_action :check_authorization

  def index
    @agent_invites = Current.account.agent_invites.includes(:team, :inviter).order(created_at: :desc)
  end

  def create
    @agent_invite = Current.account.agent_invites.create!(permitted_params.merge(inviter: Current.user))
  end

  def destroy
    @agent_invite.destroy!
    head :ok
  end

  private

  def fetch_invite
    @agent_invite = Current.account.agent_invites.find(params[:id])
  end

  def permitted_params
    params.require(:agent_invite).permit(:role, :team_id)
  end
end
