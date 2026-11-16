require 'rails_helper'

describe Whatsapp::Evolution::HistoryImportService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(inbox: inbox, since: 30.days.ago) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'evolution', validate_provider_config: false, sync_templates: false,
                              provider_config: { 'base_url' => 'https://evo.test', 'instance' => 'contas_a_receber', 'api_key' => 'k' })
  end
  let(:inbox) { channel.inbox }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:group_jid) { '120363000000000001@g.us' }
  let(:now) { Time.zone.parse('2026-11-16 12:00') }
  let(:records) do
    [
      { 'key' => { 'id' => 'M3', 'remoteJid' => group_jid, 'fromMe' => false, 'participant' => '5511988887777@s.whatsapp.net' },
        'pushName' => 'Cliente', 'messageType' => 'conversation', 'message' => { 'conversation' => 'boleto venceu?' },
        'messageTimestamp' => (now - 1.day).to_i },
      { 'key' => { 'id' => 'M2', 'remoteJid' => group_jid, 'fromMe' => true },
        'messageType' => 'conversation', 'message' => { 'conversation' => 'segue o boleto' },
        'messageTimestamp' => (now - 3.days).to_i },
      { 'key' => { 'id' => 'M1', 'remoteJid' => group_jid, 'fromMe' => false, 'participant' => '5511988887777@s.whatsapp.net' },
        'pushName' => 'Cliente', 'messageType' => 'conversation', 'message' => { 'conversation' => 'antigo demais' },
        'messageTimestamp' => (now - 40.days).to_i }
    ]
  end

  before do
    travel_to now
    WhatsappGroup.create!(account: account, jid: group_jid, subject: 'Financeiro Cliente X', instance: 'contas_a_receber',
                          instances: ['contas_a_receber'])
    stub_request(:post, 'https://evo.test/chat/findChats/contas_a_receber')
      .to_return(status: 200, headers: json, body: [
        { remoteJid: group_jid, updatedAt: (now - 1.day).iso8601 },
        { remoteJid: '5511900000000@s.whatsapp.net', updatedAt: (now - 60.days).iso8601 },
        { remoteJid: 'status@broadcast', updatedAt: now.iso8601 }
      ].to_json)
    stub_request(:post, 'https://evo.test/chat/findMessages/contas_a_receber')
      .to_return(status: 200, headers: json, body: { messages: { total: 3, pages: 1, currentPage: 1, records: records } }.to_json)
    stub_request(:get, %r{evo\.test/group/findGroupInfos}).to_return(status: 200, headers: json, body: { subject: 'Financeiro Cliente X' }.to_json)
  end

  it 'imports the window oldest first, keeping the time each message was sent' do
    service.perform

    messages = inbox.messages.reorder(:id)
    expect(messages.map(&:source_id)).to eq(%w[M2 M3])
    expect(messages.map(&:created_at)).to eq([now - 3.days, now - 1.day])
    expect(messages.first).to be_outgoing
    expect(messages.last.content_attributes['group_participant']).to include('phone_number' => '5511988887777')
  end

  it 'only reads the chats active in the window' do
    service.perform

    expect(a_request(:post, 'https://evo.test/chat/findMessages/contas_a_receber')).to have_been_made.once
  end

  it 'only fills gaps when run again' do
    service.perform

    expect { described_class.new(inbox: inbox, since: 30.days.ago).perform }.not_to change(Message, :count)
  end

  it 'never sends anything through the read-only inbox' do
    perform_enqueued_jobs(only: SendReplyJob) { service.perform }

    expect(a_request(:post, %r{evo\.test/message/})).not_to have_been_made
  end
end
