# Shared by every CRM mirror: the CRMs hand over bare digits while Chatwoot stores E.164,
# so a literal comparison never matches and cards end up with no contact at all.
module Crm::ContactMatcher
  module_function

  # The CRMs keep numbers as typed by people, mostly Brazilian and mostly without the
  # country code, so national numbers are read as Brazilian.
  DEFAULT_COUNTRY_CODE = '55'.freeze

  # Both spellings are checked so the lookup still uses the phone_number index. Brazilian
  # mobiles are also tried with and without the ninth digit: WhatsApp still reports many of
  # them in the old eight-digit form, which is how those contacts were saved in Chatwoot.
  def by_phone(account, value)
    digits = normalize_phone(value)&.delete('+') || value.to_s.gsub(/\D/, '')
    return nil if digits.blank?

    candidates = [digits, brazilian_variant(digits)].compact
    account.contacts.find_by(phone_number: candidates.flat_map { |number| [number, "+#{number}"] })
  end

  # Returns the number in E.164, or nil when it cannot be a real phone. A number Chatwoot
  # cannot dial is better left out than saved wrong, since campaigns send to it.
  def normalize_phone(value)
    raw = value.to_s.strip
    digits = raw.gsub(/\D/, '').sub(/\A0+/, '')
    return nil if digits.blank?

    international = raw.start_with?('+') || (digits.start_with?(DEFAULT_COUNTRY_CODE) && digits.length.between?(12, 13))
    e164 = "+#{with_ninth_digit(international ? digits : "#{DEFAULT_COUNTRY_CODE}#{digits}")}"
    TelephoneNumber.parse(e164).valid? ? e164 : nil
  end

  def brazilian_variant(digits)
    if (match = digits.match(/\A55(\d{2})9([6-9]\d{7})\z/))
      "55#{match[1]}#{match[2]}"
    elsif (match = digits.match(/\A55(\d{2})([6-9]\d{7})\z/))
      "55#{match[1]}9#{match[2]}"
    end
  end

  # Old eight-digit mobiles still circulate in CRMs; the ninth digit has been mandatory in
  # Brazil since 2016, and WhatsApp resolves the modern form for every one of them.
  def with_ninth_digit(digits)
    match = digits.match(/\A55(\d{2})([6-9]\d{7})\z/)
    match ? "55#{match[1]}9#{match[2]}" : digits
  end
end
