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

  pattr_initialize [:account!, :label_ids!, { segment_ids: [] }]

  def self.for_campaign(campaign)
    ids = ->(type) { campaign.audience.select { |item| item['type'] == type }.pluck('id') }
    new(account: campaign.account, label_ids: ids.call('Label'), segment_ids: ids.call('Segment'))
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
    scope = audience.where(blocked: false).where.not(phone_number: [nil, '']).where.not(id: opted_out.select(:id))
    self.class.test_mode? ? scope.where(phone_number: self.class.test_numbers) : scope
  end

  def summary
    {
      audience: audience.count,
      without_phone: audience.where(phone_number: [nil, '']).count,
      opted_out: audience.where(id: opted_out.select(:id)).count,
      blocked: audience.where(blocked: true).count,
      recipients: recipients.count,
      test_mode: self.class.test_mode?,
      sample: recipients.reorder(:id).limit(SAMPLE_SIZE).map { |contact| { name: contact.name, phone_number: contact.phone_number } }
    }
  end

  private

  def label_titles
    @label_titles ||= account.labels.where(id: label_ids).pluck(:title)
  end

  # Anyone carrying one of the labels or matching one of the segments. A segment is a saved
  # contact filter, read at send time, so contacts imported since it was saved are included.
  def audience
    @audience ||= audience_sources.map { |source| account.contacts.where(id: source.unscope(:order, :limit, :offset).reselect('contacts.id')) }
                                  .reduce(:or) || account.contacts.none
  end

  def audience_sources
    sources = segment_contacts
    sources << account.contacts.tagged_with(label_titles, any: true) if label_titles.any?
    sources
  end

  def segment_contacts
    account.custom_filters.contact.where(id: segment_ids).map do |segment|
      Contacts::FilterService.new(account, segment.user, segment.query.with_indifferent_access).perform[:contacts]
    end
  end

  def opted_out
    account.contacts.tagged_with(OPT_OUT_LABEL)
  end
end
