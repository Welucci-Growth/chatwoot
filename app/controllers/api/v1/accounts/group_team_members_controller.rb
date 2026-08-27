class Api::V1::Accounts::GroupTeamMembersController < Api::V1::Accounts::BaseController
  before_action :ensure_administrator

  def index
    render json: { team: Current.account.group_team_members.order(:name) }
  end

  def create
    member = Current.account.group_team_members.find_or_initialize_by(
      phone_number: params[:phone_number].to_s.split('@').first.gsub(/\D/, '')
    )
    member.name = params[:name]
    member.source = 'manual'
    member.save!
    render json: { member: member }
  end

  def destroy
    Current.account.group_team_members.find(params[:id]).destroy!
    head :ok
  end

  # Pulls the staff phones straight from the Evolution instances so the roster starts full.
  def sync
    Whatsapp::Evolution::GroupService.new.sync_team_from_instances
    render json: { team: Current.account.group_team_members.order(:name) }
  end

  private

  def ensure_administrator
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end
