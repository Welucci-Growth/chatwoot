require 'rails_helper'

describe Whatsapp::Evolution::LidResolutionService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'evolution', validate_provider_config: false, sync_templates: false,
                              provider_config: { 'base_url' => 'https://evo.test', 'instance' => 'contas_a_receber', 'api_key' => 'k' })
  end
  let(:inbox) { channel.inbox }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let!(:revealed) { create(:contact, account: account, name: '252206180000000', phone_number: '+252206180000000') }
  let!(:hidden) { create(:contact, account: account, name: '171360806523055', phone_number: '+171360806523055') }

  before do
    create(:contact_inbox, inbox: inbox, contact: revealed, source_id: '252206180000000')
    create(:contact_inbox, inbox: inbox, contact: hidden, source_id: '171360806523055')
    stub_request(:post, 'https://evo.test/chat/findChats/contas_a_receber')
      .to_return(status: 200, headers: json, body: [{ remoteJid: '252206180000000@lid' }, { remoteJid: '171360806523055@lid' },
                                                    { remoteJid: '5511900000000@s.whatsapp.net' }].to_json)
    stub_request(:post, 'https://evo.test/chat/findMessages/contas_a_receber')
      .with(body: hash_including(where: { key: { remoteJid: '252206180000000@lid' } }))
      .to_return(status: 200, headers: json, body: { messages: { pages: 1, records: [
        { key: { id: 'A', remoteJid: '252206180000000@lid' } },
        { key: { id: 'B', remoteJid: '252206180000000@lid', remoteJidAlt: '5511988887777@s.whatsapp.net' } }
      ] } }.to_json)
    stub_request(:post, 'https://evo.test/chat/findMessages/contas_a_receber')
      .with(body: hash_including(where: { key: { remoteJid: '171360806523055@lid' } }))
      .to_return(status: 200, headers: json, body: { messages: { pages: 1,
                                                                 records: [{ key: { id: 'C', remoteJid: '171360806523055@lid' } }] } }.to_json)
  end

  it 'gives each LID contact its real number, or names it as hidden' do
    expect(described_class.new(inbox: inbox).perform).to eq(linked: 1, hidden: 1)

    expect(revealed.reload).to have_attributes(name: '+5511988887777', phone_number: '+5511988887777')
    expect(hidden.reload).to have_attributes(name: 'Number hidden by WhatsApp · 3055', phone_number: nil)
  end

  it 'folds a LID contact into the contact that already owns the number' do
    owner = create(:contact, account: account, name: 'Fornecedor', phone_number: '+5511988887777')

    described_class.new(inbox: inbox).perform

    expect(Contact.exists?(revealed.id)).to be(false)
    expect(inbox.contact_inboxes.find_by(source_id: '252206180000000').contact).to eq(owner)
  end

  it 'fires no contact events' do
    expect(Rails.configuration.dispatcher.async_dispatcher).not_to receive(:dispatch)
    expect(Rails.configuration.dispatcher.sync_dispatcher).not_to receive(:dispatch)

    described_class.new(inbox: inbox).perform
  end
end
