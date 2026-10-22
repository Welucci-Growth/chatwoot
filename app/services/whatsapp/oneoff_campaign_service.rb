class Whatsapp::OneoffCampaignService
  pattr_initialize [:campaign!]

  # Hands the audience to Campaigns::WhatsappBatchJob, which marks the campaign completed
  # once the last batch has been sent.
  def perform
    validate_campaign!
    Campaigns::WhatsappBatchJob.perform_later(campaign.id)
  end

  private

  delegate :inbox, to: :campaign
  delegate :channel, to: :inbox

  def validate_campaign_type!
    raise "Invalid campaign #{campaign.id}" unless whatsapp_campaign? && campaign.one_off?
  end

  def whatsapp_campaign?
    campaign.inbox.inbox_type == 'Whatsapp'
  end

  def validate_campaign_status!
    raise 'Completed Campaign' if campaign.completed?
  end

  def validate_provider!
    raise 'WhatsApp Cloud provider required' if channel.provider != 'whatsapp_cloud'
  end

  def validate_feature_flag!
    raise 'WhatsApp campaigns feature not enabled' unless campaign.account.feature_enabled?(:whatsapp_campaign)
  end

  def validate_template_params!
    raise 'WhatsApp campaign has no template' if campaign.template_params.blank?
  end

  def validate_campaign!
    validate_campaign_type!
    validate_campaign_status!
    validate_provider!
    validate_feature_flag!
    validate_template_params!
  end
end
