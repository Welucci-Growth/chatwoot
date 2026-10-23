require 'rails_helper'

describe Crm::Hubspot::ContactSyncService do
  let(:account) { create(:account) }
  let(:hook) do
    create(:integrations_hook, account: account, app_id: 'hubspot',
                               settings: { 'access_token' => 'hs-token', 'contact_list_ids' => '42' })
  end
  let(:members) { %w[101 102] }
  let(:people) do
    [
      { 'id' => '101',
        'properties' => { 'firstname' => 'Ana', 'lastname' => 'Souza', 'email' => 'ana@example.com', 'mobilephone' => '(11) 98888-7777' } },
      { 'id' => '102', 'properties' => { 'firstname' => 'Bruno', 'email' => 'bruno@example.com', 'phone' => '21 3333-4444' } }
    ]
  end
  let(:hubspot_contacts) { account.contacts.where("additional_attributes -> 'external' ->> 'hubspot_id' IS NOT NULL") }

  before do
    stub_request(:get, %r{api\.hubapi\.com/crm/v3/properties/contacts/}).to_return(status: 404, body: '')
    stub_request(:get, %r{api\.hubapi\.com/crm/v3/owners})
      .to_return(status: 200, body: { results: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, 'https://api.hubapi.com/crm/v3/lists/42')
      .to_return(status: 200, body: { list: { listId: '42', name: 'Clientes VIP' } }.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, %r{api\.hubapi\.com/crm/v3/lists/42/memberships})
      .to_return do
        { status: 200, body: { results: members.map { |id| { recordId: id } } }.to_json, headers: { 'Content-Type' => 'application/json' } }
      end
    stub_request(:post, 'https://api.hubapi.com/crm/v3/objects/contacts/batch/read')
      .to_return { { status: 200, body: { results: people }.to_json, headers: { 'Content-Type' => 'application/json' } } }
  end

  it 'imports the list members as contacts carrying the list label' do
    expect(described_class.new(hook).perform).to eq('42' => 2)

    ana = account.contacts.from_email('ana@example.com')
    expect(ana).to have_attributes(name: 'Ana Souza', phone_number: '+5511988887777', label_list: ['hs-clientes-vip'])
    expect(account.contacts.from_email('bruno@example.com').phone_number).to eq('+552133334444')
    expect(account.labels.find_by(title: 'hs-clientes-vip').show_on_sidebar).to be(false)
    expect(hook.reload.settings['list_labels']).to eq('42' => 'hs-clientes-vip')
  end

  it 'never sends a message' do
    expect { described_class.new(hook).perform }.not_to change(Message, :count)
  end

  it 'links an existing contact saved without the ninth digit instead of creating a twin' do
    existing = create(:contact, account: account, name: '551188887777', phone_number: '+551188887777')

    described_class.new(hook).perform

    expect(existing.reload).to have_attributes(name: 'Ana Souza', email: 'ana@example.com', phone_number: '+551188887777')
    expect(existing.label_list).to eq(['hs-clientes-vip'])
    expect(account.contacts.where(phone_number: '+5511988887777')).to be_empty
  end

  it 'keeps the data Chatwoot already has' do
    existing = create(:contact, account: account, name: 'Ana (cliente)', email: 'ana@example.com', phone_number: '+5511977776666')

    described_class.new(hook).perform

    expect(existing.reload).to have_attributes(name: 'Ana (cliente)', phone_number: '+5511977776666')
  end

  it 'is idempotent' do
    described_class.new(hook).perform

    expect { described_class.new(hook.reload).perform }.not_to change(account.contacts, :count)
    expect(ActsAsTaggableOn::Tagging.where(taggable_type: 'Contact', context: 'labels').count).to eq(2)
  end

  it 'removes the label from whoever left the list' do
    described_class.new(hook).perform
    members.replace(%w[101])

    described_class.new(hook.reload).perform

    expect(account.contacts.from_email('bruno@example.com').label_list).to be_empty
    expect(account.contacts.from_email('ana@example.com').label_list).to eq(['hs-clientes-vip'])
  end

  it 'keeps the labels when HubSpot cannot be read' do
    described_class.new(hook).perform
    stub_request(:get, %r{api\.hubapi\.com/crm/v3/lists/42/memberships}).to_return(status: 500, body: 'oops')

    expect(described_class.new(hook.reload).perform).to eq('42' => nil)
    expect(hubspot_contacts.tagged_with('hs-clientes-vip').count).to eq(2)
  end

  it 'clears the label of a list taken out of the integration' do
    described_class.new(hook).perform
    hook.reload.update!(settings: hook.settings.merge('contact_list_ids' => ''))

    described_class.new(hook.reload).perform

    expect(hubspot_contacts.tagged_with('hs-clientes-vip').count).to eq(0)
    expect(hook.reload.settings['list_labels']).to eq({})
  end

  it 'skips people with neither a valid email nor a valid phone' do
    people << { 'id' => '103', 'properties' => { 'firstname' => 'Sem contato', 'email' => 'invalido', 'phone' => '123' } }
    members << '103'

    expect(described_class.new(hook).perform).to eq('42' => 2)
  end
end
