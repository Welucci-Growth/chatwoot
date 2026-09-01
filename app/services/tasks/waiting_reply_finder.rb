# The board is where an agent decides who to answer next, so a card needs to know whether the
# last word in the conversation was the client's — and since when.
class Tasks::WaitingReplyFinder
  def initialize(account, contact_ids)
    @account = account
    @contact_ids = Array(contact_ids).compact.uniq
  end

  # contact_id => the moment the client wrote, for the contacts still waiting on an answer.
  def perform
    return {} if @contact_ids.blank?

    last_messages.each_with_object({}) do |message, waiting|
      waiting[message.contact_id] = message.created_at if message.incoming?
    end
  end

  private

  # One row per contact: the last thing said either way, across all of their conversations.
  # Message orders by created_at by default, which DISTINCT ON refuses, hence the reorder.
  def last_messages
    Message.joins(:conversation)
           .select('DISTINCT ON (conversations.contact_id) conversations.contact_id, messages.message_type, messages.created_at')
           .where(account_id: @account.id, message_type: [:incoming, :outgoing], private: false)
           .where(conversations: { contact_id: @contact_ids })
           .reorder('conversations.contact_id, messages.created_at DESC')
  end
end
