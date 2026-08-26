# Reads and manages WhatsApp groups through the Evolution server that already backs the
# mirror inbox. Only non-messaging operations are exposed: nothing here sends a message or
# adds a participant, which are the actions that put a number at risk.
class Whatsapp::Evolution::GroupService
  CACHE_TTL = 30.minutes
  READ_TIMEOUT = 90

  def connected_instances
    request(:get, '/instance/fetchInstances')
      .select { |i| i['connectionStatus'] == 'open' }
      .map { |i| { name: i['name'], profile_name: i['profileName'] } }
  end

  # A single instance takes up to 40 seconds and the whole fleet takes minutes, far beyond any
  # HTTP timeout. The dashboard therefore reads the cache and a background job fills it.
  #
  # Redis rather than Rails.cache on purpose: this installation's Rails.cache is a FileStore,
  # local to each container, so a cache written by the job in Sidekiq would be invisible to
  # the web process that has to serve it.
  def cached_groups(instance)
    raw = ::Redis::Alfred.get(cache_key(instance))
    return nil if raw.blank?

    with_conversations(JSON.parse(raw, symbolize_names: true))
  end

  # Evolution knows every group the number belongs to; Chatwoot only has a thread for the ones
  # that have spoken since the mirror was connected. Joining the two is what turns a directory
  # into something you can monitor.
  def with_conversations(groups)
    threads = conversation_index(groups.pluck(:jid))
    groups.map { |g| g.merge(threads.fetch(g[:jid], {})) }
  end

  def sync_groups(instance)
    groups = fetch_groups(instance)
    ::Redis::Alfred.setex(cache_key(instance), groups.to_json, CACHE_TTL)
    groups
  end

  def expire(instance)
    ::Redis::Alfred.delete(cache_key(instance))
  end

  def fetch_groups(instance)
    request(:get, "/group/fetchAllGroups/#{instance}", getParticipants: false).map do |g|
      {
        instance: instance,
        jid: g['id'],
        subject: g['subject'],
        description: g['desc'],
        size: g['size'],
        owner: g['owner'],
        announce_only: g['announce'],
        locked: g['restrict'],
        created_at: g['creation']
      }
    end
  end

  def participants(instance, jid)
    body = request(:get, "/group/participants/#{instance}", groupJid: jid)
    Array(body['participants']).map do |p|
      { id: p['id'], admin: p['admin'] }
    end
  end

  def invite_code(instance, jid)
    request(:get, "/group/inviteCode/#{instance}", groupJid: jid)['inviteCode']
  end

  def revoke_invite_code(instance, jid)
    request(:post, "/group/revokeInviteCode/#{instance}", { groupJid: jid })['inviteCode']
  end

  def update_subject(instance, jid, subject)
    request(:post, "/group/updateGroupSubject/#{instance}", { groupJid: jid }, { subject: subject })
    expire(instance)
  end

  def update_description(instance, jid, description)
    request(:post, "/group/updateGroupDescription/#{instance}", { groupJid: jid }, { description: description })
    expire(instance)
  end

  # Only promotion and demotion are allowed. Adding or removing members is deliberately
  # not implemented: mass membership changes are the classic trigger for a number ban.
  def update_admin(instance, jid, participant, action)
    raise ArgumentError, "unsupported action #{action}" unless %w[promote demote].include?(action)

    request(:post, "/group/updateParticipant/#{instance}", { groupJid: jid },
            { action: action, participants: [participant] })
  end

  private

  def conversation_index(jids)
    inbox = channel.inbox
    ContactInbox.where(inbox_id: inbox.id, source_id: jids)
                .includes(conversations: :messages)
                .each_with_object({}) do |ci, acc|
      conversation = ci.conversations.max_by(&:id)
      next if conversation.blank?

      acc[ci.source_id] = {
        conversation_id: conversation.display_id,
        message_count: conversation.messages.size,
        unread_count: conversation.messages.count { |m| m.incoming? && m.created_at > seen_at(conversation) },
        last_activity_at: conversation.last_activity_at
      }
    end
  end

  def seen_at(conversation)
    conversation.agent_last_seen_at || Time.zone.at(0)
  end

  def cache_key(instance)
    "evolution_groups/#{channel.id}/#{instance}"
  end

  def channel
    @channel ||= Channel::Whatsapp.find_by!(provider: 'evolution')
  end

  def base_url
    channel.provider_config['base_url'].to_s.chomp('/')
  end

  def request(method, path, query = {}, body = nil)
    response = HTTParty.public_send(
      method,
      "#{base_url}#{path}",
      query: query.presence,
      body: body&.to_json,
      headers: { 'apikey' => channel.provider_config['api_key'], 'Content-Type' => 'application/json' },
      timeout: READ_TIMEOUT
    )
    raise "Evolution #{method.to_s.upcase} #{path} failed: #{response.code} #{response.body.to_s.first(200)}" unless response.success?

    response.parsed_response
  end
end
