# Shared by every CRM mirror: the CRMs hand over bare digits while Chatwoot stores E.164,
# so a literal comparison never matches and cards end up with no contact at all.
module Crm::ContactMatcher
  module_function

  # Both spellings are checked so the lookup still uses the phone_number index.
  def by_phone(account, value)
    digits = value.to_s.gsub(/\D/, '')
    return nil if digits.blank?

    account.contacts.find_by(phone_number: [digits, "+#{digits}"])
  end
end
