require 'rails_helper'

describe Whatsapp::CampaignRecipientService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { whatsapp_channel.inbox }
  let(:contact) { create(:contact, account: account, name: 'Ana', phone_number: '+5511988887777') }
  let(:campaign) do
    create(:campaign, inbox: inbox, account: account, message: 'Olá {{contact.name}}',
                      template_params: {
                        'name' => 'ticket_status_updated', 'namespace' => '23423423_2342423_324234234_2343224',
                        'language' => 'en', 'category' => 'UTILITY',
                        'processed_params' => { 'body' => { 'name' => '{{contact.name}}', 'ticket_id' => '2332' } }
                      })
  end
  let(:service) { described_class.new(campaign: campaign, contact: contact) }
  let(:campaign_messages) { Message.where("(additional_attributes -> 'campaign_id') @> ?::jsonb", campaign.id.to_s) }

  it 'sends the template as an outgoing message in a snoozed conversation' do
    service.perform

    message = campaign_messages.sole
    expect(message).to have_attributes(message_type: 'outgoing', content: 'Olá Ana')
    expect(message.additional_attributes['template_params']['processed_params']).to eq('body' => { 'name' => 'Ana', 'ticket_id' => '2332' })
    expect(message.conversation).to have_attributes(status: 'snoozed', campaign_id: campaign.id, contact_id: contact.id)
    expect(SendReplyJob).to have_been_enqueued.with(message.id)
  end

  it 'delivers through WhatsApp and records the provider message id' do
    send_request = stub_request(:post, /graph\.facebook\.com.*messages/)
                   .with { |request| JSON.parse(request.body).values_at('to', 'type') == %w[5511988887777 template] }
                   .to_return(status: 200, body: { messages: [{ id: 'wamid.campaign' }] }.to_json, headers: { 'Content-Type' => 'application/json' })

    perform_enqueued_jobs(only: SendReplyJob) { service.perform }

    expect(send_request).to have_been_requested.once
    expect(campaign_messages.sole.source_id).to eq('wamid.campaign')
  end

  it 'reuses the conversation already under way' do
    ongoing = create(:conversation, account: account, inbox: inbox, contact: contact, status: :open)

    service.perform

    expect(campaign_messages.sole.conversation).to eq(ongoing)
  end

  it 'never sends the same campaign twice to a contact' do
    service.perform

    expect { described_class.new(campaign: campaign, contact: contact).perform }.not_to change(campaign_messages, :count)
  end

  it 'skips a contact whose template variables render blank' do
    contact.update!(name: '')

    expect { service.perform }.not_to change(Message, :count)
  end
end
