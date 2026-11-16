require 'rails_helper'

RSpec.describe 'Evolution webhook', type: :request do
  let(:channel) do
    create(:channel_whatsapp, provider: 'evolution', validate_provider_config: false, sync_templates: false,
                              provider_config: { 'base_url' => 'https://evo.test', 'instance' => 'contas_a_pagar', 'api_key' => 'k' })
  end
  let(:token) { channel.provider_config['webhook_verify_token'] }
  let(:payload) { { event: 'messages.upsert', instance: 'contas_a_pagar', data: { key: { remoteJid: '5511988887777@s.whatsapp.net' } } } }

  it 'mirrors a live message' do
    post "/webhooks/evolution/#{token}", params: payload, as: :json

    expect(Webhooks::EvolutionEventsJob).to have_been_enqueued
  end

  it 'holds live messages while the number history is being imported' do
    channel.update_columns(provider_config: channel.provider_config.merge('mirror_paused' => true)) # rubocop:disable Rails/SkipsModelValidations

    post "/webhooks/evolution/#{token}", params: payload, as: :json

    expect(response).to have_http_status(:ok)
    expect(Webhooks::EvolutionEventsJob).not_to have_been_enqueued
  end
end
