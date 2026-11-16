# Brings the recent history of an Evolution number into its mirror inbox, chat by chat and
# oldest message first. Messages already mirrored are skipped by their WhatsApp id, so running
# it again only fills gaps.
class Whatsapp::Evolution::HistoryImportService
  PAGE_SIZE = 100
  # The live mirror holds this lock per chat while it writes; taking the same one keeps an
  # import and a live message from creating the same conversation twice.
  LOCK_TIMEOUT = 30.seconds

  pattr_initialize [:inbox!, :since!]

  # Returns how many history records it went through.
  def perform
    chat_jids.sum { |jid| import_chat(jid) }
  end

  private

  def channel
    inbox.channel
  end

  def chat_jids
    request("/chat/findChats/#{instance}", {}).filter_map do |chat|
      jid = chat['remoteJid'].to_s
      next if jid.blank? || jid.end_with?('@broadcast')
      next if Time.zone.parse(chat['updatedAt'].to_s).to_i < since.to_i

      jid
    end
  end

  # One chat that fails (an expired media, a malformed record) must not stop the others.
  def import_chat(jid)
    records = recent_records(jid).sort_by { |record| record['messageTimestamp'].to_i }
    records.each { |record| import_record(record) }
    records.size
  rescue StandardError => e
    Rails.logger.error("[EVOLUTION_HISTORY] #{instance} #{jid}: #{e.message}")
    0
  end

  # Evolution lists a chat newest first and ignores date filters, so pages are read until they
  # reach messages older than the window.
  def recent_records(jid)
    (1..).each_with_object([]) do |page, records|
      body = request("/chat/findMessages/#{instance}", { where: { key: { remoteJid: jid } }, page: page, offset: PAGE_SIZE })['messages']
      batch = Array(body['records'])
      records.concat(batch.select { |record| record['messageTimestamp'].to_i >= since.to_i })
      break records if batch.empty? || page >= body['pages'].to_i || batch.last['messageTimestamp'].to_i < since.to_i
    end
  end

  def import_record(record)
    lock_key = format(::Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: inbox.id, sender_id: record.dig('key', 'remoteJid'))
    Redis::LockManager.new.with_lock(lock_key, LOCK_TIMEOUT) do
      Whatsapp::Evolution::HistoryMessageService.new(
        inbox: inbox,
        params: { event: 'messages.upsert', data: record },
        outgoing_echo: record.dig('key', 'fromMe').present?
      ).perform
    end
  end

  def instance
    channel.provider_config['instance']
  end

  def request(path, body)
    response = HTTParty.post("#{channel.provider_config['base_url'].to_s.chomp('/')}#{path}",
                             headers: channel.provider_service.api_headers, body: body.to_json, timeout: 120)
    raise "Evolution POST #{path} failed: #{response.code}" unless response.success?

    response.parsed_response
  end
end
