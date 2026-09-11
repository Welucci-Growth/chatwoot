# LUCI calls this when a client reaches out, so the lead lands on the HubSpot board the sales
# team works from without anyone retyping it.
class Api::V1::Accounts::LuciLeadsController < Api::V1::Accounts::BaseController
  before_action :ensure_allowed

  def create
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    render json: Crm::Hubspot::LeadCreationService.new(conversation).perform
  end

  private

  # The bridge calls with its bot token; humans need to be administrators.
  def ensure_allowed
    return if Current.user.is_a?(AgentBot)

    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?
  end
end
