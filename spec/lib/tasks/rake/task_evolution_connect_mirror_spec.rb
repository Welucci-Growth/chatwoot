require 'rake'
require 'rails_helper'

RSpec.describe Rake::Task do
  subject(:task) { described_class['evolution:connect_mirror'] }

  let(:account) { create(:account) }
  let(:json) { { 'Content-Type' => 'application/json' } }

  before do
    task.reenable
    create(:channel_whatsapp, account: account, provider: 'evolution', validate_provider_config: false, sync_templates: false,
                              provider_config: { 'base_url' => 'https://evo.test', 'instance' => 'douglas_novais', 'api_key' => 'k' })
    stub_request(:get, 'https://evo.test/instance/fetchInstances')
      .to_return(status: 200, headers: json, body: [{ name: 'contas_a_pagar', connectionStatus: 'open',
                                                      ownerJid: '5511955550000@s.whatsapp.net' }].to_json)
    stub_request(:get, 'https://evo.test/instance/connectionState/contas_a_pagar')
      .to_return(status: 200, headers: json, body: { instance: { state: 'open' } }.to_json)
  end

  it 'connects the number paused, without auto assignment, and queues its history import' do
    expect { task.invoke('contas_a_pagar', 'Contas a Pagar', '30') }.to output(/importando 30 dias/).to_stdout

    inbox = account.inboxes.find_by!(name: 'Contas a Pagar')
    expect(inbox.channel).to have_attributes(provider: 'evolution', phone_number: '+5511955550000')
    expect(inbox.channel.provider_config).to include('instance' => 'contas_a_pagar', 'mirror_paused' => true, 'base_url' => 'https://evo.test')
    expect(inbox).to have_attributes(enable_auto_assignment: false, lock_to_single_conversation: true)
    expect(Whatsapp::Evolution::HistoryImportJob).to have_been_enqueued.with(inbox.id, 30)
  end

  it 'refuses a number that is not connected in Evolution' do
    expect { task.invoke('nao_existe', 'X', '30') }.to raise_error(/no connected instance named nao_existe/)
  end
end
