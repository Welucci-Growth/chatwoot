class Api::V1::Accounts::LuciSettingsController < Api::V1::Accounts::BaseController
  before_action :ensure_allowed

  def show
    render json: {
      settings: settings,
      models: LuciSetting::MODELS,
      inboxes: bot_inboxes,
      stats: stats
    }
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

  # What she actually did, so the screen reports reality instead of only holding settings.
  def stats
    bot = Current.account.agent_bots.find_by(name: 'LUCI')
    since = 30.days.ago
    handled = Conversation.where(account_id: Current.account.id)
                          .joins(:taggings).where(taggings: { tag_id: luci_tag_id })
                          .where('conversations.created_at > ?', since).count
    replies = bot ? Message.where(account_id: Current.account.id, sender: bot).where('created_at > ?', since).count : 0

    { conversations: handled, replies: replies, since_days: 30 }
  end

  def luci_tag_id
    ActsAsTaggableOn::Tag.where(name: settings.required_label).select(:id)
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
