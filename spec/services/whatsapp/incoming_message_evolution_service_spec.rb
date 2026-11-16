require 'rails_helper'

describe Whatsapp::IncomingMessageEvolutionService do
  let(:channel) do
    create(:channel_whatsapp, provider: 'evolution', validate_provider_config: false, sync_templates: false,
                              provider_config: { 'base_url' => 'https://evo.test', 'instance' => 'contas_a_pagar', 'api_key' => 'k' })
  end
  let(:params) do
    { event: 'messages.upsert',
      data: { key: { id: SecureRandom.hex(8), remoteJid: '252206180000000@lid', remoteJidAlt: '5511988887777@s.whatsapp.net', fromMe: false },
              pushName: 'Fornecedor', messageType: 'conversation', message: { conversation: 'oi' }, messageTimestamp: Time.current.to_i } }
  end

  it 'files a chat addressed by LID under the real phone number' do
    described_class.new(inbox: channel.inbox, params: params).perform

    expect(channel.inbox.messages.sole.sender.phone_number).to eq('+5511988887777')
  end

  context 'when WhatsApp hides the number behind the LID' do
    let(:inbox) { channel.inbox }
    let(:lid_only) do
      { event: 'messages.upsert',
        data: { key: { id: SecureRandom.hex(8), remoteJid: '252206180000000@lid', fromMe: false },
                pushName: '252206180000000', messageType: 'conversation', message: { conversation: 'e o boleto?' },
                messageTimestamp: Time.current.to_i } }
    end

    it 'names the contact as hidden instead of passing the LID off as a phone' do
      described_class.new(inbox: inbox, params: lid_only).perform

      expect(inbox.messages.sole.sender).to have_attributes(name: 'Number hidden by WhatsApp · 0000', phone_number: nil)
    end

    it 'names the contact as hidden when the team wrote first' do
      echo = lid_only.deep_merge(data: { key: { fromMe: true } })
      described_class.new(inbox: inbox, params: echo, outgoing_echo: true).perform

      expect(inbox.conversations.sole.contact).to have_attributes(name: 'Number hidden by WhatsApp · 0000', phone_number: nil)
    end

    it 'keeps the messages without the number on the contact that has it' do
      described_class.new(inbox: inbox, params: params).perform
      described_class.new(inbox: inbox, params: lid_only).perform

      expect(inbox.conversations.count).to eq(1)
      expect(inbox.contacts.distinct.sole).to have_attributes(name: 'Fornecedor', phone_number: '+5511988887777')
    end

    it 'gives the hidden contact the number once WhatsApp reveals it' do
      described_class.new(inbox: inbox, params: lid_only).perform
      described_class.new(inbox: inbox, params: params.deep_merge(data: { pushName: '252206180000000' })).perform

      expect(inbox.conversations.count).to eq(1)
      expect(inbox.contacts.distinct.sole).to have_attributes(name: '+5511988887777', phone_number: '+5511988887777')
    end

    it 'folds the hidden contact into the contact that already owns the number' do
      owner = create(:contact, account: inbox.account, name: 'Fornecedor (HubSpot)', phone_number: '+5511988887777')
      described_class.new(inbox: inbox, params: lid_only).perform
      described_class.new(inbox: inbox, params: params).perform

      expect(inbox.account.contacts.where(id: inbox.contacts.select(:id)).to_a).to eq([owner])
      expect(owner.reload.name).to eq('Fornecedor (HubSpot)')
      expect(inbox.messages.map(&:sender).uniq).to eq([owner])
    end
  end
end
