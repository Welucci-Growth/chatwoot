require 'rails_helper'

describe Whatsapp::Evolution::HistoryImportJob do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'evolution', validate_provider_config: false, sync_templates: false,
                              provider_config: { 'base_url' => 'https://evo.test', 'instance' => 'contas_a_pagar', 'api_key' => 'k',
                                                 'mirror_paused' => true })
  end
  let(:json) { { 'Content-Type' => 'application/json' } }

  before do
    stub_request(:get, 'https://evo.test/instance/connectionState/contas_a_pagar')
      .to_return(status: 200, headers: json, body: { instance: { state: 'open' } }.to_json)
    stub_request(:post, 'https://evo.test/chat/findChats/contas_a_pagar')
      .to_return(status: 200, headers: json, body: [{ remoteJid: '5511988887777@s.whatsapp.net', updatedAt: Time.current.iso8601 }].to_json)
    stub_request(:post, 'https://evo.test/chat/findMessages/contas_a_pagar')
      .to_return(status: 200, headers: json, body: { messages: { total: 1, pages: 1, records: [
        { key: { id: 'P1', remoteJid: '5511988887777@s.whatsapp.net', fromMe: false }, pushName: 'Fornecedor',
          messageType: 'conversation', message: { conversation: 'nota fiscal anexa' }, messageTimestamp: 2.days.ago.to_i }
      ] } }.to_json)
  end

  it 'imports the history and then turns the live mirror on' do
    described_class.perform_now(channel.inbox.id, 30)

    expect(channel.inbox.messages.pluck(:source_id)).to eq(['P1'])
    expect(channel.reload.provider_config).not_to have_key('mirror_paused')
  end

  it 'replays no event for the imported history' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
    inbox = channel.inbox

    described_class.perform_now(inbox.id, 30)

    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(Events::Types::MESSAGE_CREATED, any_args)
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(Events::Types::CONVERSATION_CREATED, any_args)
  end
end
