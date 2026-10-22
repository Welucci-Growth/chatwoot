# Sends a campaign to one contact as an ordinary outgoing message, so it goes through the same
# path as an agent's template: it is tracked on the message (sent, delivered, read, failed and
# why) and sits in a conversation where the reply will land.
class Whatsapp::CampaignRecipientService
  pattr_initialize [:campaign!, :contact!]

  def perform
    return if already_sent?

    if template_params.nil?
      Rails.logger.info "[CAMPAIGN] #{campaign.id}: skipping contact #{contact.id}, template variables rendered blank"
      return
    end

    conversation.messages.create!(
      account_id: campaign.account_id,
      inbox_id: campaign.inbox_id,
      message_type: :outgoing,
      sender: campaign.sender,
      content: campaign.message,
      additional_attributes: { campaign_id: campaign.id, template_params: template_params }
    )
  end

  private

  def template_params
    @template_params ||= Whatsapp::LiquidTemplateProcessorService.new(campaign: campaign, contact: contact)
                                                                 .process_template_params(campaign.template_params)
  end

  # A batch retried after a crash must not reach the same person twice.
  def already_sent?
    Message.joins(:conversation)
           .where(inbox_id: campaign.inbox_id, conversations: { contact_id: contact.id })
           .exists?(["(messages.additional_attributes -> 'campaign_id') @> ?::jsonb", campaign.id.to_s])
  end

  # An ongoing conversation is reused so the campaign reads in context. Otherwise a snoozed
  # one is opened: it stays out of the agents' way, and the customer's reply reopens it with
  # the campaign message right above.
  def conversation
    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: campaign.inbox).perform

    contact.conversations.where(inbox_id: campaign.inbox_id).where.not(status: :resolved).last ||
      Conversation.create!(account_id: campaign.account_id, inbox_id: campaign.inbox_id, contact: contact,
                           contact_inbox: contact_inbox, campaign: campaign, status: :snoozed)
  end
end
