# Reads and manages WhatsApp groups through the Evolution server that already backs the
# mirror inbox. Only non-messaging operations are exposed: nothing here sends a message or
# adds a participant, which are the actions that put a number at risk.
class Whatsapp::Evolution::GroupService
  CACHE_TTL = 5.minutes
  READ_TIMEOUT = 90

  def connected_instances
    request(:get, '/instance/fetchInstances')
      .select { |i| i['connectionStatus'] == 'open' }
      .map { |i| { name: i['name'], profile_name: i['profileName'] } }
  end

  # Evolution needs tens of seconds per instance, so the dashboard asks for one instance at a
  # time instead of one aggregate call that would outlive any HTTP timeout.
  def groups_for(instance, force: false)
    key = cache_key(instance)
    Rails.cache.delete(key) if force

    Rails.cache.fetch(key, expires_in: CACHE_TTL) { fetch_groups(instance) }
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
    Rails.cache.delete(cache_key(instance))
  end

  def update_description(instance, jid, description)
    request(:post, "/group/updateGroupDescription/#{instance}", { groupJid: jid }, { description: description })
    Rails.cache.delete(cache_key(instance))
  end

  # Only promotion and demotion are allowed. Adding or removing members is deliberately
  # not implemented: mass membership changes are the classic trigger for a number ban.
  def update_admin(instance, jid, participant, action)
    raise ArgumentError, "unsupported action #{action}" unless %w[promote demote].include?(action)

    request(:post, "/group/updateParticipant/#{instance}", { groupJid: jid },
            { action: action, participants: [participant] })
  end

  private

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
