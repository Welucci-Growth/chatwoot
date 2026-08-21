# Translates an Evolution `messages.upsert` event into the Cloud API payload shape so the
# whole contact/conversation/attachment pipeline in the base service is reused as-is.
#
# Evolution payload:
#   { event: 'messages.upsert', data: { key: { remoteJid:, fromMe:, id:, participant: },
#     pushName:, messageType:, message: { conversation: 'hi' }, messageTimestamp: } }
class Whatsapp::IncomingMessageEvolutionService < Whatsapp::IncomingMessageBaseService
  TYPE_MAP = {
    'conversation' => 'text',
    'extendedTextMessage' => 'text',
    'imageMessage' => 'image',
    'videoMessage' => 'video',
    'audioMessage' => 'audio',
    'documentMessage' => 'document',
    'documentWithCaptionMessage' => 'document',
    'stickerMessage' => 'sticker',
    'locationMessage' => 'location',
    'contactMessage' => 'contacts',
    'reactionMessage' => 'reaction'
  }.freeze

  GROUP_JID_SUFFIX = '@g.us'.freeze

  private

  # Events we cannot render (poll updates, protocol receipts) translate to an empty hash,
  # which makes the base service's perform a no-op.
  def processed_params
    @processed_params ||= mapped_type.blank? ? {} : translated_payload
  end

  def download_attachment_file(attachment_payload)
    encoded = inbox.channel.provider_service.fetch_media_base64(attachment_payload[:key])
    return if encoded.blank?

    mime_type = attachment_payload[:mime_type].to_s.split(';').first
    filename = attachment_payload[:filename].presence || default_filename(mime_type)

    file = StringIO.new(Base64.decode64(encoded))
    file.define_singleton_method(:original_filename) { filename }
    file.define_singleton_method(:content_type) { mime_type }
    file
  end

  def translated_payload
    return { message_echoes: [message_payload] } if from_me?

    { contacts: [contact_payload], messages: [message_payload] }
  end

  def contact_payload
    return { profile: { name: group_name }, user_id: remote_jid } if group?

    { profile: { name: data[:pushName] }, wa_id: phone_number }
  end

  def message_payload
    {
      id: message_key[:id],
      timestamp: data[:messageTimestamp],
      type: mapped_type
    }.merge(identifier_fields, content_fields, context_fields)
  end

  # Group JIDs are longer than a phone number, so they travel as a bare source id
  # instead of a phone identifier. The base service handles a contact with no number.
  def identifier_fields
    if group?
      from_me? ? { to_user_id: remote_jid } : { from_user_id: remote_jid }
    else
      from_me? ? { to: phone_number } : { from: phone_number }
    end
  end

  def content_fields
    case mapped_type
    when 'text' then { text: { body: decorate(text_body) } }
    when 'location' then { location: location_payload }
    when 'contacts' then { contacts: [shared_contact_payload] }
    else { mapped_type.to_sym => media_payload }
    end
  end

  def context_fields
    quoted_id = message_node.dig('extendedTextMessage', 'contextInfo', 'stanzaId')
    quoted_id.present? ? { context: { id: quoted_id } } : {}
  end

  def media_payload
    {
      key: message_key,
      caption: decorate(media_node['caption']),
      filename: media_node['fileName'],
      mime_type: media_node['mimetype']
    }
  end

  def location_payload
    node = message_node['locationMessage'] || {}
    {
      latitude: node['degreesLatitude'],
      longitude: node['degreesLongitude'],
      name: node['name'],
      address: node['address']
    }
  end

  # Evolution ships shared contacts as a vCard; the WhatsApp id inside it is the only
  # reliable phone number, since the DisplayName is free text.
  def shared_contact_payload
    node = message_node['contactMessage'] || {}
    waid = node['vcard'].to_s[/waid=(\d+)/, 1]
    {
      'name' => { 'formatted_name' => node['displayName'] },
      'phones' => waid.present? ? [{ phone: "+#{waid}" }] : []
    }
  end

  def text_body
    message_node['conversation'].presence || message_node.dig('extendedTextMessage', 'text')
  end

  # Chatwoot has no group model, so every group message lands in one conversation and the
  # participant's name is prefixed to the body to keep the thread readable.
  def decorate(content)
    return content unless group? && !from_me? && content.present?

    "#{data[:pushName]}: #{content}"
  end

  def group_name
    inbox.channel.provider_service.fetch_group_subject(remote_jid).presence || remote_jid.split('@').first
  end

  def default_filename(mime_type)
    extension = Rack::Mime::MIME_TYPES.invert[mime_type].to_s.delete('.').presence || 'bin'
    "#{message_key[:id]}.#{extension}"
  end

  def media_node
    node = message_node['documentWithCaptionMessage']
    return node.dig('message', 'documentMessage') || {} if node.present?

    message_node[evolution_type] || {}
  end

  def mapped_type
    TYPE_MAP[evolution_type]
  end

  def evolution_type
    @evolution_type ||= data[:messageType].presence || message_node.keys.first
  end

  def message_node
    @message_node ||= data[:message].to_h.with_indifferent_access
  end

  def message_key
    @message_key ||= data[:key].to_h.with_indifferent_access
  end

  def remote_jid
    message_key[:remoteJid].to_s
  end

  def group?
    remote_jid.end_with?(GROUP_JID_SUFFIX)
  end

  def from_me?
    message_key[:fromMe].present?
  end

  def phone_number
    remote_jid.split('@').first
  end

  def data
    @data ||= params[:data].to_h.with_indifferent_access
  end
end
