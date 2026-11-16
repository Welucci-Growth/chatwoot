class Api::V1::Accounts::Conversations::AssignmentsController < Api::V1::Accounts::Conversations::BaseController
  before_action :restrict_monitoring_assignment
  # assigns agent/team to a conversation
  def create
    if params.key?(:assignee_id) || agent_bot_assignment?
      set_agent
    elsif params.key?(:team_id)
      set_team
    else
      render json: nil
    end
  end

  private

  # A monitoring team hands conversations to each other only: never to a team, a bot or someone
  # outside the profile. Unassigning stays open to them.
  def restrict_monitoring_assignment
    return unless Current.account_user&.monitoring?
    raise Pundit::NotAuthorizedError if params.key?(:team_id) || agent_bot_assignment?
    # The dashboard unassigns by sending 0.
    return if params[:assignee_id].to_i.zero?

    raise Pundit::NotAuthorizedError unless @conversation.inbox.monitoring_peers.exists?(id: params[:assignee_id])
  end

  def set_agent
    resource = Conversations::AssignmentService.new(
      conversation: @conversation,
      assignee_id: params[:assignee_id],
      assignee_type: params[:assignee_type]
    ).perform

    render_agent(resource)
  end

  def render_agent(resource)
    case resource
    when User
      render partial: 'api/v1/models/agent', formats: [:json], locals: { resource: resource }
    when AgentBot
      render partial: 'api/v1/models/agent_bot_slim', formats: [:json], locals: { resource: resource }
    else
      render json: nil
    end
  end

  def set_team
    @team = Current.account.teams.find_by(id: params[:team_id])
    @conversation.update!(team: @team)
    render json: @team
  end

  def agent_bot_assignment?
    params[:assignee_type].to_s == 'AgentBot'
  end
end
