class Api::V1::Accounts::EvolutionGroupsController < Api::V1::Accounts::BaseController
  before_action :ensure_administrator
  before_action :set_service

  # The dashboard loads one instance at a time; a single aggregate call would outlive the
  # request timeout, since Evolution takes tens of seconds per instance.
  def index
    render json: { instances: @service.connected_instances }
  end

  # Never blocks: returns whatever is cached and schedules a refresh when there is nothing yet.
  def by_instance
    @service.expire(instance) if params[:refresh].present?
    groups = @service.cached_groups(instance)

    if groups.nil?
      Whatsapp::Evolution::GroupSyncJob.perform_later(instance)
      render json: { groups: [], pending: true }
    else
      render json: { groups: groups, pending: false }
    end
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
