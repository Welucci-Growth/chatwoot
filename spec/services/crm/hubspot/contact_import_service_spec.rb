require 'rails_helper'

describe Crm::Hubspot::ContactImportService do
  let(:account) { create(:account) }
  let(:hook) do
    create(:integrations_hook, account: account, app_id: 'hubspot', settings: { 'access_token' => 'hs-token' })
  end
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:ana) do
    { 'id' => '101', 'properties' => { 'firstname' => 'Ana', 'lastname' => 'Souza', 'email' => 'ana@example.com',
                                       'mobilephone' => '(11) 98888-7777', 'lifecyclestage' => 'customer',
                                       'hubspot_owner_id' => '9', 'city' => 'São Paulo' } }
  end
  let(:bruno) { { 'id' => '102', 'properties' => { 'firstname' => 'Bruno', 'phone' => '21 99999-1111', 'lifecyclestage' => 'lead' } } }
  let(:no_phone) { { 'id' => '103', 'properties' => { 'firstname' => 'Sem', 'email' => 'sem@telefone.com' } } }

  before do
    stub_request(:get, 'https://api.hubapi.com/crm/v3/properties/contacts/lifecyclestage')
      .to_return(status: 200, headers: json, body: { name: 'lifecyclestage', options: [{ value: 'lead', label: 'Lead' },
                                                                                       { value: 'customer', label: 'Cliente' }] }.to_json)
    stub_request(:get, %r{api\.hubapi\.com/crm/v3/properties/contacts/(city|state|company)})
      .to_return(status: 200, headers: json, body: { name: 'text', options: [] }.to_json)
    stub_request(:get, %r{api\.hubapi\.com/crm/v3/properties/contacts/(hs_lead_status|hs_analytics_source|origem)})
      .to_return(status: 404, body: '')
    stub_request(:get, %r{api\.hubapi\.com/crm/v3/owners})
      .to_return(status: 200, headers: json, body: { results: [{ id: '9', firstName: 'Carla', lastName: 'Vendas' }] }.to_json)
    stub_request(:get, %r{api\.hubapi\.com/crm/v3/objects/contacts\?})
      .with(query: hash_excluding('after'))
      .to_return(status: 200, headers: json, body: { results: [ana, no_phone], paging: { next: { after: 'page-2' } } }.to_json)
    stub_request(:get, %r{api\.hubapi\.com/crm/v3/objects/contacts\?})
      .with(query: hash_including('after' => 'page-2'))
      .to_return(status: 200, headers: json, body: { results: [bruno] }.to_json)
  end

  it 'imports every contact with a phone, with the HubSpot fields as filterable attributes' do
    expect(described_class.new(hook).perform).to eq(2)

    contact = account.contacts.from_email('ana@example.com')
    expect(contact).to have_attributes(name: 'Ana Souza', phone_number: '+5511988887777', contact_type: 'lead', location: 'São Paulo')
    expect(contact.custom_attributes).to include('hubspot_etapa' => 'Cliente', 'hubspot_vendedor' => 'Carla Vendas', 'hubspot_cidade' => 'São Paulo')
    expect(account.contacts.find_by(phone_number: '+5521999991111').custom_attributes['hubspot_etapa']).to eq('Lead')
    expect(account.contacts.from_email('sem@telefone.com')).to be_nil
  end

  it 'keeps the attribute definitions in step with HubSpot, skipping properties the portal lacks' do
    described_class.new(hook).perform

    definitions = account.custom_attribute_definitions.where(attribute_model: :contact_attribute).index_by(&:attribute_key)
    expect(definitions['hubspot_etapa']).to have_attributes(attribute_display_type: 'list', attribute_values: %w[Lead Cliente])
    expect(definitions['hubspot_vendedor'].attribute_values).to eq(['Carla Vendas'])
    expect(definitions['hubspot_cidade'].attribute_display_type).to eq('text')
    expect(definitions).not_to have_key('hubspot_status_lead')
  end

  it 'fires no contact event, so webhooks and automations never hear about the import' do
    create(:contact, account: account, name: '5511988887777', phone_number: '+5511988887777')
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

    described_class.new(hook).perform

    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(Events::Types::CONTACT_CREATED, any_args)
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(Events::Types::CONTACT_UPDATED, any_args)
  end

  it 'updates the contact Chatwoot already has, keeping its own phone' do
    existing = create(:contact, account: account, name: 'Ana (cliente)', email: 'ana@example.com', phone_number: '+5511977776666')

    described_class.new(hook).perform

    expect(existing.reload).to have_attributes(name: 'Ana (cliente)', phone_number: '+5511977776666')
    expect(existing.custom_attributes['hubspot_etapa']).to eq('Cliente')
    expect(existing.additional_attributes.dig('external', 'hubspot_id')).to eq('101')
  end

  it 'resumes an interrupted import from the saved cursor' do
    hook.update!(settings: hook.settings.merge('contacts_import' => { 'started_at' => 1.hour.ago.iso8601, 'cursor' => 'page-2' }))

    expect(described_class.new(hook).perform).to eq(1)
    expect(account.contacts.from_email('ana@example.com')).to be_nil
  end

  it 'reads only what changed once the first import is done' do
    described_class.new(hook).perform
    changed = bruno.deep_merge('properties' => { 'lifecyclestage' => 'customer' })
    search = stub_request(:post, 'https://api.hubapi.com/crm/v3/objects/contacts/search')
             .to_return(status: 200, headers: json, body: { results: [changed] }.to_json)

    described_class.new(hook.reload).perform

    expect(search).to have_been_requested.once
    expect(account.contacts.find_by(phone_number: '+5521999991111').custom_attributes['hubspot_etapa']).to eq('Cliente')
    expect(account.contacts.count).to eq(2)
  end

  it 'never sends a message' do
    expect { described_class.new(hook).perform }.not_to change(Message, :count)
  end
end
