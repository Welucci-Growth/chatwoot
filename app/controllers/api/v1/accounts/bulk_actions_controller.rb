class Api::V1::Accounts::BulkActionsController < Api::V1::Accounts::BaseController
  def create
    case normalized_type
    when 'Conversation'
      restrict_monitoring_bulk_assignment
      enqueue_conversation_job
      head :ok
    when 'Contact'
      check_authorization_for_contact_action
      enqueue_contact_job
      head :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  private

  def normalized_type
    params[:type].to_s.camelize
  end

  # Same rule as a single assignment: a monitoring team only hands conversations to each other.
  def restrict_monitoring_bulk_assignment
    return unless Current.account_user&.monitoring?

    fields = params[:fields] || {}
    raise Pundit::NotAuthorizedError if fields[:team_id].present?
    raise Pundit::NotAuthorizedError unless fields[:assignee_id].to_i.zero? || monitoring_peer_everywhere?(fields[:assignee_id])
  end

  def monitoring_peer_everywhere?(user_id)
    inboxes = Current.account.inboxes.where(id: Current.account.conversations.where(display_id: params[:ids]).select(:inbox_id))
    inboxes.all? { |inbox| inbox.monitoring_peers.exists?(id: user_id) }
  end

  def enqueue_conversation_job
    ::BulkActionsJob.perform_later(
      account: @current_account,
      user: current_user,
      params: conversation_params
    )
  end

  def enqueue_contact_job
    Contacts::BulkActionJob.perform_later(
      @current_account.id,
      current_user.id,
      contact_params
    )
  end

  def delete_contact_action?
    params[:action_name] == 'delete'
  end

  def check_authorization_for_contact_action
    authorize(Contact, :destroy?) if delete_contact_action?
  end

  def conversation_params
    # TODO: Align conversation payloads with the `{ action_name, action_attributes }`
    # and then remove this method in favor of a common params method.
    base = params.permit(
      :snoozed_until,
      fields: [:status, :assignee_id, :team_id]
    )
    append_common_bulk_attributes(base)
  end

  def contact_params
    # TODO: remove this method in favor of a common params method.
    # once legacy conversation payloads are migrated.
    # The filter is the same contact filter payload the list was fetched with; FilterService
    # validates every attribute and operator in it.
    base = params[:filter].present? ? { filter: params.require(:filter).permit!.to_h } : {}
    append_common_bulk_attributes(base)
  end

  def append_common_bulk_attributes(base_params)
    # NOTE: Conversation payloads historically diverged per action. Going forward we
    # want all objects to share a common contract: `{ action_name, action_attributes }`
    common = params.permit(:type, :action_name, ids: [], exclude_ids: [], labels: [add: [], remove: []])
    base_params.merge(common)
  end
end
