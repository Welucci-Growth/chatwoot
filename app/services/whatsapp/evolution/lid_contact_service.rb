# WhatsApp hides many numbers behind an opaque LID and reveals the real one only on some
# messages. Once the number is known, the contact first saved under the bare LID takes it, or
# folds into the contact that already owns it, so nobody shows up twice or as a random number.
# While the number stays hidden, the contact is named as hidden instead of passing the LID off
# as a phone that campaigns would try to dial.
class Whatsapp::Evolution::LidContactService
  pattr_initialize [:inbox!, :lid!]

  def self.hidden_name(account, lid)
    I18n.with_locale(account.locale) { I18n.t('contacts.whatsapp_hidden_number', suffix: lid.last(4)) }
  end

  def link(phone)
    return if lid_contact.blank?

    owner = Crm::ContactMatcher.by_phone(account, "+#{phone}")
    if owner && owner != lid_contact
      ContactMergeAction.new(account: account, base_contact: owner, mergee_contact: lid_contact).perform
    else
      lid_contact.update!(phone_number: "+#{phone}", name: placeholder_name? ? "+#{phone}" : lid_contact.name)
    end
  end

  def hide
    return if lid_contact.blank?

    lid_contact.phone_number = nil if fake_phone?
    lid_contact.name = self.class.hidden_name(account, lid) if placeholder_name?
    lid_contact.save! if lid_contact.changed?
  end

  def placeholder_name?
    lid_contact.name.in?([lid, "+#{lid}", self.class.hidden_name(account, lid)])
  end

  def lid_contact
    @lid_contact ||= inbox.contact_inboxes.find_by(source_id: lid)&.contact
  end

  private

  def fake_phone?
    lid_contact.phone_number == "+#{lid}"
  end

  def account
    inbox.account
  end
end
