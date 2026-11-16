require 'rails_helper'

describe Whatsapp::IncomingMessageEvolutionService do
  let(:channel) do
    create(:channel_whatsapp, provider: 'evolution', validate_provider_config: false, sync_templates: false,
                              provider_config: { 'base_url' => 'https://evo.test', 'instance' => 'contas_a_pagar', 'api_key' => 'k' })
  end
  let(:params) do
    { event: 'messages.upsert',
      data: { key: { id: 'L1', remoteJid: '252206180000000@lid', remoteJidAlt: '5511988887777@s.whatsapp.net', fromMe: false },
              pushName: 'Fornecedor', messageType: 'conversation', message: { conversation: 'oi' }, messageTimestamp: Time.current.to_i } }
  end

  it 'files a chat addressed by LID under the real phone number' do
    described_class.new(inbox: channel.inbox, params: params).perform

    expect(channel.inbox.messages.sole.sender.phone_number).to eq('+5511988887777')
  end
end
