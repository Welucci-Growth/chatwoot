# One-off repair for contacts mirrored before the LID handling existed: they were saved with the
# LID as their name and as a fake phone number. Each one either gets the real number, found on
# any message of its chat, or is named as hidden. Nothing here fires contact events.
class Whatsapp::Evolution::LidResolutionService
  PAGE_SIZE = 100

  pattr_initialize [:inbox!]

  def perform
    Dispatcher.silently do
      lid_jids.each_with_object(Hash.new(0)) do |jid, result|
        lid = jid.delete_suffix('@lid')
        contacts = Whatsapp::Evolution::LidContactService.new(inbox: inbox, lid: lid)
        next if contacts.lid_contact.blank?

        phone = known_number(jid)
        outcome = phone ? :linked : :hidden
        done = with_chat_lock(jid) { phone ? contacts.link(phone) : contacts.hide }
        result[done ? outcome : :busy] += 1
      end
    end
  end

  private

  def lid_jids
    request("/chat/findChats/#{instance}", {}).map { |chat| chat['remoteJid'].to_s }.select { |jid| jid.end_with?('@lid') }
  end

  def known_number(jid)
    page = 0
    loop do
      page += 1
      body = request("/chat/findMessages/#{instance}", { where: { key: { remoteJid: jid } }, page: page, offset: PAGE_SIZE })['messages']
      alt = Array(body['records']).filter_map { |record| record.dig('key', 'remoteJidAlt').presence }.first
      break alt.split('@').first if alt
      break if page >= body['pages'].to_i
    end
  end

  # The live mirror may be writing to the same chat.
  def with_chat_lock(jid, &)
    key = format(::Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: inbox.id, sender_id: jid)
    Redis::LockManager.new.with_lock(key, 30.seconds, &)
  end

  def instance
    inbox.channel.provider_config['instance']
  end

  def request(path, body)
    response = HTTParty.post("#{inbox.channel.provider_config['base_url'].to_s.chomp('/')}#{path}",
                             headers: inbox.channel.provider_service.api_headers, body: body.to_json, timeout: 120)
    raise "Evolution POST #{path} failed: #{response.code}" unless response.success?

    response.parsed_response
  end
end
