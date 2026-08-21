# Evolution API is an unofficial WhatsApp bridge that mirrors an existing WhatsApp Web
# session. Inboxes on this provider are read-only on purpose: we observe the session and
# never originate traffic through it, which is what keeps the connected number safe.
class Whatsapp::Providers::EvolutionService < Whatsapp::Providers::BaseService
  def send_message(_phone_number, _message)
    raise 'Evolution inboxes are read-only'
  end

  def send_template(_phone_number, _template_info, _message)
    raise 'Evolution inboxes are read-only'
  end

  def sync_templates
    # Evolution has no template registry, so there is nothing to sync.
  end

  def validate_provider_config?
    response = HTTParty.get("#{base_url}/instance/connectionState/#{instance}", headers: api_headers)
    response.success? && response.parsed_response.dig('instance', 'state') == 'open'
  end

  def api_headers
    { 'apikey' => whatsapp_channel.provider_config['api_key'], 'Content-Type' => 'application/json' }
  end

  # Evolution exposes media per message rather than by a stable media id, so the incoming
  # service fetches it through this method instead of the shared `media_url` contract.
  def fetch_media_base64(message_key)
    response = HTTParty.post(
      "#{base_url}/chat/getBase64FromMediaMessage/#{instance}",
      headers: api_headers,
      body: { message: { key: message_key } }.to_json
    )
    return unless response.success?

    response.parsed_response['base64']
  end

  def fetch_group_subject(group_jid)
    response = HTTParty.get(
      "#{base_url}/group/findGroupInfos/#{instance}",
      headers: api_headers,
      query: { groupJid: group_jid }
    )
    return unless response.success?

    response.parsed_response['subject']
  end

  private

  def base_url
    whatsapp_channel.provider_config['base_url'].to_s.chomp('/')
  end

  def instance
    whatsapp_channel.provider_config['instance']
  end
end
