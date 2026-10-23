require 'rails_helper'

RSpec.describe 'HubSpot Integration API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:hook) do
    create(:integrations_hook, account: account, app_id: 'hubspot',
                               settings: { 'access_token' => 'hs-token', 'contact_list_ids' => '42' })
  end
  let(:segments_url) { "/api/v1/accounts/#{account.id}/integrations/hubspot/segments" }

  describe 'GET segments' do
    before do
      stub_request(:post, 'https://api.hubapi.com/crm/v3/lists/search')
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: {
          lists: [
            { listId: '42', name: 'Clientes VIP', objectTypeId: '0-1', processingType: 'DYNAMIC', additionalProperties: { hs_list_size: '120' } },
            { listId: '43', name: 'Leads SP', objectTypeId: '0-1', processingType: 'MANUAL', additionalProperties: { hs_list_size: '8' } },
            { listId: '44', name: 'Negócios abertos', objectTypeId: '0-3', processingType: 'DYNAMIC' }
          ],
          hasMore: false
        }.to_json)
    end

    it 'lists the contact segments with the ones already chosen' do
      get segments_url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['segments']).to eq([
                                                       { 'id' => '42', 'name' => 'Clientes VIP', 'size' => 120, 'dynamic' => true,
                                                         'selected' => true },
                                                       { 'id' => '43', 'name' => 'Leads SP', 'size' => 8, 'dynamic' => false,
                                                         'selected' => false }
                                                     ])
    end

    it 'explains when HubSpot refuses the call' do
      stub_request(:post, 'https://api.hubapi.com/crm/v3/lists/search').to_return(status: 403, body: 'missing scopes')

      get segments_url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('403')
    end

    it 'is limited to administrators' do
      get segments_url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH segments' do
    it 'saves the chosen segments and mirrors them straight away' do
      expect do
        patch segments_url, params: { segment_ids: %w[42 43] }, headers: admin.create_new_auth_token, as: :json
      end.to have_enqueued_job(Crm::SetupJob).with(hook.id)

      expect(response).to have_http_status(:ok)
      expect(hook.reload.settings['contact_list_ids']).to eq('42,43')
    end

    it 'is limited to administrators' do
      patch segments_url, params: { segment_ids: %w[43] }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(hook.reload.settings['contact_list_ids']).to eq('42')
    end
  end
end
