class Api::V1::Accounts::LuciSettingsController < Api::V1::Accounts::BaseController
  before_action :ensure_allowed

  def show
    render json: { settings: settings, models: LuciSetting::MODELS, inboxes: bot_inboxes }
  end

  def update
    settings.update!(permitted_params)
    render json: { settings: settings }
  end

  private

  def settings
    @settings ||= LuciSetting.for_account(Current.account)
  end

  def permitted_params
    params.permit(:system_prompt, :knowledge, :model, :required_label, :enabled)
  end

  # Which inboxes LUCI currently answers on, so the screen states it rather than implying it.
  def bot_inboxes
    bot = Current.account.agent_bots.find_by(name: 'LUCI')
    return [] if bot.blank?

    Inbox.where(id: AgentBotInbox.where(agent_bot_id: bot.id).select(:inbox_id)).pluck(:name)
  end

  # The bridge reads this with its bot token; humans need to be administrators.
  def ensure_allowed
    return if Current.user.is_a?(AgentBot)
    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?
  end
end
