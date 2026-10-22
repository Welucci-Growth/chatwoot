# Decides who a WhatsApp campaign reaches. The same rules back the preview shown before a
# campaign is created and the send itself, so the number the team sees is the number sent.
class Whatsapp::CampaignAudienceService
  # Anyone carrying this label is never sent a campaign, whatever other labels they have.
  OPT_OUT_LABEL = 'nao-enviar'.freeze
  # While set, campaigns only reach these numbers, however large the chosen audience is. It
  # lives in the environment so a campaign can be tried in production without any customer
  # receiving it, and nobody can switch it off from the dashboard by mistake.
  TEST_NUMBERS_ENV = 'CAMPAIGN_TEST_PHONE_NUMBERS'.freeze
  SAMPLE_SIZE = 5

  pattr_initialize [:account!, :label_ids!]

  def self.for_campaign(campaign)
    new(account: campaign.account, label_ids: campaign.audience.select { |item| item['type'] == 'Label' }.pluck('id'))
  end

  # Each number is matched with and without the Brazilian ninth digit, as contacts are saved.
  def self.test_numbers
    ENV.fetch(TEST_NUMBERS_ENV, '').split(',').filter_map { |number| Crm::ContactMatcher.normalize_phone(number) }.flat_map do |number|
      variant = Crm::ContactMatcher.brazilian_variant(number.delete('+'))
      [number, variant && "+#{variant}"].compact
    end
  end

  def self.test_mode?
    ENV.fetch(TEST_NUMBERS_ENV, '').strip.present?
  end

  def recipients
    scope = labelled.where(blocked: false).where.not(phone_number: [nil, '']).where.not(id: opted_out.select(:id))
    self.class.test_mode? ? scope.where(phone_number: self.class.test_numbers) : scope
  end

  def summary
    {
      labelled: labelled.count,
      without_phone: labelled.where(phone_number: [nil, '']).count,
      opted_out: labelled.where(id: opted_out.select(:id)).count,
      blocked: labelled.where(blocked: true).count,
      recipients: recipients.count,
      test_mode: self.class.test_mode?,
      sample: recipients.reorder(:id).limit(SAMPLE_SIZE).map { |contact| { name: contact.name, phone_number: contact.phone_number } }
    }
  end

  private

  def label_titles
    @label_titles ||= account.labels.where(id: label_ids).pluck(:title)
  end

  def labelled
    return account.contacts.none if label_titles.empty?

    account.contacts.tagged_with(label_titles, any: true)
  end

  def opted_out
    account.contacts.tagged_with(OPT_OUT_LABEL)
  end
end
