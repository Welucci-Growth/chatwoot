# A card is linked to its Chatwoot contact while the CRM mirror runs, so a client who only
# started talking to us after the last change to the deal is never linked: the sync revisits
# a card when the deal moves, not when a conversation begins. The panel resolves the link the
# first time someone opens the card, and keeps it.
module Crm::ContactLinker
  module_function

  def link(task, phones)
    return task.contact if task.contact_id.present?

    contact = Array(phones).lazy.filter_map { |phone| Crm::ContactMatcher.by_phone(task.account, phone) }.first
    task.update!(contact_id: contact.id) if contact
    contact
  end
end
