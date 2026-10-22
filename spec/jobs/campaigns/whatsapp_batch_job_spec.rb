require 'rails_helper'

describe Campaigns::WhatsappBatchJob do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:label) { create(:label, account: account) }
  let(:campaign) do
    create(:campaign, inbox: whatsapp_channel.inbox, account: account, audience: [{ type: 'Label', id: label.id }],
                      template_params: { 'name' => 'promo', 'language' => 'pt_BR', 'processed_params' => {} })
  end
  let!(:contacts) do
    Array.new(3) { |index| create(:contact, account: account, phone_number: "+55119888877#{index}0", label_list: [label.title]) }
  end

  before { stub_const("#{described_class}::BATCH_SIZE", 2) }

  it 'sends a batch and queues the next one after the last contact it reached' do
    described_class.perform_now(campaign.id)

    expect(Message.count).to eq(2)
    expect(described_class).to have_been_enqueued.with(campaign.id, contacts.second.id)
    expect(campaign.reload).not_to be_completed
  end

  it 'completes the campaign after the last batch' do
    described_class.perform_now(campaign.id, contacts.second.id)

    expect(Message.count).to eq(1)
    expect(campaign.reload).to be_completed
  end

  it 'carries on when one contact fails' do
    allow(Whatsapp::CampaignRecipientService).to receive(:new).and_call_original
    allow(Whatsapp::CampaignRecipientService).to receive(:new).with(campaign: campaign, contact: contacts.first).and_raise('boom')

    described_class.perform_now(campaign.id)

    expect(Message.count).to eq(1)
  end

  it 'does nothing for a completed campaign' do
    campaign.completed!

    expect { described_class.perform_now(campaign.id) }.not_to change(Message, :count)
  end
end
