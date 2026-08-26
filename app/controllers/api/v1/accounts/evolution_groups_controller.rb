class Api::V1::Accounts::EvolutionGroupsController < Api::V1::Accounts::BaseController
  before_action :ensure_administrator
  before_action :set_service

  def index
    render json: { groups: @service.all_groups(force: params[:refresh].present?) }
  end

  def details
    render json: {
      participants: @service.participants(instance, jid),
      invite_code: @service.invite_code(instance, jid)
    }
  end

  def update_group
    @service.update_subject(instance, jid, params[:subject]) if params[:subject].present?
    @service.update_description(instance, jid, params[:description]) if params[:description].present?
    head :ok
  end

  def revoke_invite
    render json: { invite_code: @service.revoke_invite_code(instance, jid) }
  end

  def update_admin
    @service.update_admin(instance, jid, params[:participant], params[:action_type])
    head :ok
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_service
    @service = Whatsapp::Evolution::GroupService.new
  end

  def instance
    params[:instance]
  end

  def jid
    params[:jid]
  end

  def ensure_administrator
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end
