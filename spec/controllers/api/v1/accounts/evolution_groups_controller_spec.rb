require 'rails_helper'

RSpec.describe 'Evolution groups API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:finance) { create(:user, account: account, role: :agent) }
  let(:groups_url) { "/api/v1/accounts/#{account.id}/evolution_groups" }
  let!(:finance_channel) do
    create(:channel_whatsapp, account: account, provider: 'evolution', validate_provider_config: false, sync_templates: false,
                              provider_config: { 'base_url' => 'https://evo.test', 'instance' => 'contas_a_receber', 'api_key' => 'k' })
  end

  before do
    create(:inbox_member, user: finance, inbox: finance_channel.inbox)
    WhatsappGroup.create!(account: account, jid: '120363000000000001@g.us', subject: 'Cliente X', instance: 'juliana_antao',
                          instances: %w[juliana_antao contas_a_receber])
    WhatsappGroup.create!(account: account, jid: '120363000000000002@g.us', subject: 'Comercial', instance: 'juliana_antao',
                          instances: %w[juliana_antao])
  end

  it 'shows an agent only the groups of the numbers they work with, labelled with their number' do
    get groups_url, headers: finance.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['groups'].map { |g| [g['subject'], g['instance']] }).to eq([['Cliente X', 'contas_a_receber']])
  end

  it 'shows an administrator every group' do
    get groups_url, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['groups'].pluck('subject')).to contain_exactly('Cliente X', 'Comercial')
  end

  it 'links the group to the thread in the agent inbox' do
    contact = create(:contact, account: account)
    contact_inbox = create(:contact_inbox, contact: contact, inbox: finance_channel.inbox, source_id: '120363000000000001@g.us')
    conversation = create(:conversation, account: account, inbox: finance_channel.inbox, contact: contact, contact_inbox: contact_inbox)

    get groups_url, headers: finance.create_new_auth_token, as: :json

    expect(response.parsed_body['groups'].first['conversation_id']).to eq(conversation.display_id)
  end

  it 'keeps the actions that change a group with administrators' do
    post "#{groups_url}/update_group", params: { instance: 'contas_a_receber', jid: '120363000000000001@g.us', subject: 'x' },
                                       headers: finance.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
