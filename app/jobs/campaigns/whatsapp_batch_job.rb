# Works through a WhatsApp campaign a batch at a time, each batch queuing the next. A large
# audience never becomes one job that a deploy or a crash could cut halfway, and a batch that
# runs again skips whoever it already reached.
class Campaigns::WhatsappBatchJob < ApplicationJob
  queue_as :low

  BATCH_SIZE = 100

  def perform(campaign_id, after_contact_id = 0)
    campaign = Campaign.find(campaign_id)
    return if campaign.completed?

    contacts = Whatsapp::CampaignAudienceService.for_campaign(campaign).recipients
                                                .where('contacts.id > ?', after_contact_id)
                                                .reorder(:id).limit(BATCH_SIZE).to_a
    contacts.each { |contact| send_to(campaign, contact) }

    return campaign.completed! if contacts.size < BATCH_SIZE

    self.class.perform_later(campaign_id, contacts.last.id)
  end

  private

  # One contact that cannot be reached must not hold back everyone after it.
  def send_to(campaign, contact)
    Whatsapp::CampaignRecipientService.new(campaign: campaign, contact: contact).perform
  rescue StandardError => e
    Rails.logger.error "[CAMPAIGN] #{campaign.id}: contact #{contact.id} failed: #{e.message}"
  end
end
