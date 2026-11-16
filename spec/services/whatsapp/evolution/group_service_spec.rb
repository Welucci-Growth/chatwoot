require 'rails_helper'

describe Whatsapp::Evolution::GroupService do
  let(:account) { create(:account) }
  let(:stub_groups) do
    lambda do |instance, ids|
      stub_request(:get, %r{evo\.test/group/fetchAllGroups/#{instance}})
        .to_return(status: 200, headers: json, body: ids.map { |id| { id: id, subject: "Grupo #{id}", size: 3 } }.to_json)
    end
  end
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:service) { described_class.new }

  before do
    create(:channel_whatsapp, account: account, provider: 'evolution', validate_provider_config: false, sync_templates: false,
                              provider_config: { 'base_url' => 'https://evo.test', 'instance' => 'admin', 'api_key' => 'k' })
  end

  it 'keeps every number of ours that is in a group' do
    stub_groups.call('contas_a_receber', ['120363000000000001@g.us'])
    stub_groups.call('juliana_antao', ['120363000000000001@g.us'])

    service.sync_groups('contas_a_receber')
    service.sync_groups('juliana_antao')

    expect(WhatsappGroup.find_by(jid: '120363000000000001@g.us')).to have_attributes(instance: 'contas_a_receber',
                                                                                     instances: %w[
                                                                                       contas_a_receber juliana_antao
                                                                                     ])
  end

  it 'drops a number from a group it left, and the group once none of ours remains' do
    stub_groups.call('contas_a_receber', ['120363000000000001@g.us'])
    stub_groups.call('juliana_antao', ['120363000000000001@g.us'])
    service.sync_groups('contas_a_receber')
    service.sync_groups('juliana_antao')

    stub_groups.call('contas_a_receber', [])
    service.sync_groups('contas_a_receber')
    expect(WhatsappGroup.find_by(jid: '120363000000000001@g.us')).to have_attributes(instance: 'juliana_antao', instances: %w[juliana_antao])

    stub_groups.call('juliana_antao', [])
    service.sync_groups('juliana_antao')
    expect(WhatsappGroup.find_by(jid: '120363000000000001@g.us')).to be_nil
  end
end
