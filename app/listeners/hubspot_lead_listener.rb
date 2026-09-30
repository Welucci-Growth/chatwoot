# Sends a conversation to the HubSpot Leads board when it carries the label the team uses to
# select it. The label is the whole safety mechanism: HubSpot is live, and nothing reaches it
# until someone marks the conversation on purpose.
class HubspotLeadListener < BaseListener
  def message_created(event)
    message, account = extract_message_and_account(event)
    return unless message.incoming?
    return if message.private?

    label = LuciSetting.for_account(account).lead_label
    return if label.blank?
    return unless message.conversation.label_list.include?(label)

    Crm::Hubspot::CreateLeadJob.perform_later(message.conversation)
  end
end
