class MessageFinder
  def initialize(conversation, params)
    @conversation = conversation
    @params = params
  end

  def perform
    current_messages
  end

  private

  def conversation_messages
    @conversation.messages.includes(:attachments, :sender, sender: { avatar_attachment: [:blob] })
  end

  def messages
    return conversation_messages if @params[:filter_internal_messages].blank?

    conversation_messages.where.not('private = ? OR message_type = ?', true, 2)
  end

  def current_messages
    if @params[:after].present? && @params[:before].present?
      messages_between(@params[:after].to_i, @params[:before].to_i)
    elsif @params[:before].present?
      messages_before(@params[:before].to_i)
    elsif @params[:after].present?
      messages_after(@params[:after].to_i)
    else
      messages_latest
    end
  end

  # Pages walk (created_at, id) rather than id alone: messages imported from history get ids
  # newer than the conversation they belong to, and paging by id would skip them.
  def messages_after(after_id)
    messages.reorder(created_at: :asc, id: :asc).where('(messages.created_at, messages.id) > (?, ?)', *cursor(after_id)).limit(100)
  end

  def messages_before(before_id)
    messages.reorder(created_at: :desc, id: :desc).where('(messages.created_at, messages.id) < (?, ?)', *cursor(before_id)).limit(20).reverse
  end

  def messages_between(after_id, before_id)
    messages.reorder(created_at: :asc, id: :asc)
            .where('(messages.created_at, messages.id) >= (?, ?)', *cursor(after_id))
            .where('(messages.created_at, messages.id) < (?, ?)', *cursor(before_id))
            .limit(1000)
  end

  # A cursor whose message was deleted still pages from its id, the old behaviour.
  def cursor(message_id)
    @conversation.messages.where(id: message_id).pick(:created_at, :id) || [Time.zone.at(0), message_id]
  end

  def messages_latest
    messages.reorder('created_at desc').limit(20).reverse
  end
end

MessageFinder.prepend_mod_with('MessageFinder')
