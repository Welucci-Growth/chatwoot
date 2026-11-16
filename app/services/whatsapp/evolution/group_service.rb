# Reads and manages WhatsApp groups through the Evolution server that already backs the
# mirror inbox. Only non-messaging operations are exposed: nothing here sends a message or
# adds a participant, which are the actions that put a number at risk.
class Whatsapp::Evolution::GroupService
  # The largest numbers carry well over a hundred groups and Evolution answers slowly for
  # them; this runs in a background job, so waiting longer costs nobody anything.
  READ_TIMEOUT = 240

  def channel_for?(account)
    Channel::Whatsapp.exists?(provider: 'evolution', account_id: account.id)
  end

  def connected_instances
    request(:get, '/instance/fetchInstances')
      .select { |i| i['connectionStatus'] == 'open' }
      .map { |i| { name: i['name'], profile_name: i['profileName'], number: i['number'].presence || i['ownerJid'].to_s.split('@').first } }
  end

  # Groups live in the database rather than a cache: listing them takes minutes, so the
  # dashboard reads what was last synced and a background job keeps it current.
  #
  # `instances` narrows the directory to the numbers a viewer works with (nil means every
  # number), and threads are only looked up in `inboxes`, the mirror inboxes they can open.
  def stored_groups(inboxes:, instances: nil)
    scope = WhatsappGroup.where(account: channel.account)
    scope = scope.for_instances(instances) unless instances.nil?
    with_conversations(scope.order(:subject).map { |g| serialize(g, instances) }, inboxes.map(&:id))
  end

  def last_synced_at
    WhatsappGroup.where(account: channel.account).maximum(:synced_at)
  end

  # Upserts what Evolution reports and takes the number out of the groups it has left, so the
  # directory matches reality instead of only ever growing. A group is only dropped once no
  # number of ours is in it any more.
  def sync_groups(instance)
    seen = fetch_groups(instance).map { |g| upsert_group(instance, g) }
    groups = WhatsappGroup.where(account: channel.account)
    groups.for_instance(instance).where.not(jid: seen).update_all(['instances = array_remove(instances, ?)', instance]) # rubocop:disable Rails/SkipsModelValidations
    groups.where('cardinality(instances) = 0').delete_all
    groups.where(instance: instance).where.not('? = ANY(instances)', instance).update_all('instance = instances[1]') # rubocop:disable Rails/SkipsModelValidations
    seen.count
  end

  # `instance` stays the number that first reported the group, the one admin actions go through;
  # `instances` collects every number of ours that is in it.
  def upsert_group(instance, attrs)
    record = WhatsappGroup.find_or_initialize_by(account: channel.account, jid: attrs[:jid])
    record.assign_attributes(
      instance: record.instance.presence || instance, instances: record.instances | [instance],
      subject: attrs[:subject], description: attrs[:description],
      size: attrs[:size], owner: attrs[:owner], announce_only: attrs[:announce_only].present?,
      locked: attrs[:locked].present?, synced_at: Time.current
    )
    record.save!
    record.jid
  end

  # The numbers running the instances are the staff phones, so the roster seeds itself and
  # agents only have to add the people who use their own devices.
  def sync_team_from_instances
    request(:get, '/instance/fetchInstances').each do |i|
      phone = i['number'].presence || i['ownerJid'].to_s.split('@').first
      next if phone.blank?

      member = GroupTeamMember.find_or_initialize_by(account: channel.account, phone_number: phone)
      member.name = i['profileName'].presence || i['name']
      member.source = 'instance'
      member.save!
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
    stored_group(jid)&.update!(subject: subject)
  end

  def update_description(instance, jid, description)
    request(:post, "/group/updateGroupDescription/#{instance}", { groupJid: jid }, { description: description })
    stored_group(jid)&.update!(description: description)
  end

  # Only promotion and demotion are allowed. Adding or removing members is deliberately
  # not implemented: mass membership changes are the classic trigger for a number ban.
  def update_admin(instance, jid, participant, action)
    raise ArgumentError, "unsupported action #{action}" unless %w[promote demote].include?(action)

    request(:post, "/group/updateParticipant/#{instance}", { groupJid: jid },
            { action: action, participants: [participant] })
  end

  private

  def stored_group(jid)
    WhatsappGroup.find_by(account: channel.account, jid: jid)
  end

  # Evolution knows every group the number belongs to; Chatwoot only has a thread for the ones
  # that have spoken since the mirror was connected. Joining the two is what turns a directory
  # into something you can monitor.
  def with_conversations(groups, inbox_ids)
    threads = conversation_index(groups.pluck(:jid), inbox_ids)
    groups.map { |g| g.merge(threads.fetch(g[:jid], {})) }
  end

  def fetch_groups(instance)
    request(:get, "/group/fetchAllGroups/#{instance}", getParticipants: false).map do |g|
      {
        jid: g['id'], subject: g['subject'], description: g['desc'], size: g['size'],
        owner: g['owner'], announce_only: g['announce'], locked: g['restrict']
      }
    end
  end

  # A group several of our numbers are in is mirrored once per inbox; the most recently active
  # thread is the one worth opening.
  def conversation_index(jids, inbox_ids)
    latest_threads(jids, inbox_ids).transform_values { |conversation| thread_summary(conversation) }
  end

  def latest_threads(jids, inbox_ids)
    ContactInbox.where(inbox_id: inbox_ids, source_id: jids).includes(conversations: :messages).each_with_object({}) do |ci, threads|
      conversation = ci.conversations.max_by(&:id)
      next if conversation.blank?

      current = threads[ci.source_id]
      threads[ci.source_id] = conversation if current.nil? || conversation.last_activity_at.to_i > current.last_activity_at.to_i
    end
  end

  def thread_summary(conversation)
    {
      conversation_id: conversation.display_id,
      message_count: conversation.messages.size,
      unread_count: conversation.messages.count { |m| m.incoming? && m.created_at > seen_at(conversation) },
      last_activity_at: conversation.last_activity_at
    }.merge(reply_status(conversation))
  end

  # A group is waiting when the newest message came from someone outside the team, which is
  # the signal an agent actually needs: a client spoke and nobody answered.
  def reply_status(conversation)
    last = conversation.messages.max_by(&:id)
    return { status: 'idle' } if last.blank?
    return { status: 'answered' } if last.outgoing? || from_team?(last)

    { status: 'waiting', waiting_since: last.created_at, waiting_from: sender_name(last) }
  end

  def from_team?(message)
    phone = message.content_attributes.dig('group_participant', 'phone_number')
    return team_phones.include?(phone) if phone.present?

    # Messages that predate participant capture only carry the sender's name glued to the
    # body, so fall back to matching that against the roster rather than calling every old
    # message a client and raising false alarms.
    name = sender_name(message)
    name.present? && team_names.include?(name.downcase)
  end

  def sender_name(message)
    message.content_attributes.dig('group_participant', 'name').presence ||
      message.content.to_s[/\A([^:\n]{2,40}):\s/, 1]
  end

  def team_phones
    @team_phones ||= GroupTeamMember.phone_numbers_for(channel.account).to_set
  end

  def team_names
    @team_names ||= GroupTeamMember.where(account: channel.account).pluck(:name).compact_blank.to_set(&:downcase)
  end

  def seen_at(conversation)
    conversation.agent_last_seen_at || Time.zone.at(0)
  end

  # The number shown is one the viewer works with, so a finance user never sees a group labelled
  # with a colleague's instance.
  def serialize(group, visible_instances = nil)
    {
      instance: (group.instances & Array(visible_instances)).first || group.instance, jid: group.jid, subject: group.subject,
      description: group.description, size: group.size, owner: group.owner,
      announce_only: group.announce_only, locked: group.locked
    }
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
