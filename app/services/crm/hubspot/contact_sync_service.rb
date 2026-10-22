# Mirrors the HubSpot contact lists chosen in the integration as Chatwoot labels, bringing
# their members in as contacts. Campaigns pick their audience by label, so a list becomes
# something the team can send to without exporting anything.
#
# Reads from HubSpot only and never sends a message: it only decides who carries which label.
class Crm::Hubspot::ContactSyncService
  LABEL_PREFIX = 'hs-'.freeze
  LABEL_COLOR = '#ff7a59'.freeze

  def initialize(hook)
    @hook = hook
    @account = hook.account
  end

  # Returns the member count mirrored per list, nil for a list that could not be read.
  def perform
    labels = (settings['list_labels'] || {}).dup
    return {} if list_ids.empty? && labels.empty?

    release_dropped_lists(labels)
    counts = list_ids.index_with { |list_id| sync_list(list_id, labels) }

    @hook.merge_settings!('list_labels' => labels, 'contacts_synced_at' => Time.current.iso8601)
    counts
  end

  private

  def settings
    @hook.settings
  end

  def client
    @client ||= Crm::Hubspot::Api::Client.new(settings['access_token'])
  end

  def list_ids
    @list_ids ||= settings['contact_list_ids'].to_s.split(',').filter_map { |id| id.strip.presence }.uniq
  end

  # A list that fails to load keeps the labels it already had: reading the failure as an
  # empty list would strip everyone of it, and the next run would put them back.
  def sync_list(list_id, labels)
    labels[list_id] ||= label_title_for(list_id, labels)
    ensure_label(labels[list_id], list_id)

    contact_ids = resolve_contacts(client.list_member_ids(list_id))
    mirror_membership(labels[list_id], contact_ids)
    contact_ids.size
  rescue Crm::Hubspot::Api::Client::ApiError => e
    Rails.logger.error("[HUBSPOT] list #{list_id} failed: #{e.message}")
    nil
  end

  # The title is fixed on the first sync, so renaming the list in HubSpot never strands the
  # campaigns that already point at its label.
  def label_title_for(list_id, labels)
    slug = client.contact_list(list_id)&.dig('name').to_s.parameterize
    title = "#{LABEL_PREFIX}#{slug.presence || list_id}"
    labels.value?(title) ? "#{title}-#{list_id}" : title
  end

  def ensure_label(title, list_id)
    @account.labels.find_or_create_by!(title: title) do |label|
      label.description = "Espelha a lista #{list_id} do HubSpot. Atualizada automaticamente."
      label.color = LABEL_COLOR
    end
  end

  # Members already linked need no details from HubSpot, which keeps the hourly run down to
  # the membership reads once the first import is done.
  def resolve_contacts(hubspot_ids)
    linked = writer.linked_contacts(hubspot_ids)
    people = client.contacts(hubspot_ids - linked.keys, properties: properties)

    linked.values.map(&:id) + writer.write(people.values).values
  end

  def fields
    @fields ||= Crm::Hubspot::ContactFields.new(@account, client).sync_definitions!
  end

  def writer
    @writer ||= Crm::Hubspot::ContactWriter.new(@hook, fields: fields)
  end

  def properties
    (Crm::Hubspot::Api::Client::CONTACT_PROPERTIES + fields.properties).uniq
  end

  # Written straight to the taggings table: going through the model would fire a contact
  # update event per person, and a first import of a large list would flood the queues.
  def mirror_membership(title, contact_ids)
    tag = ActsAsTaggableOn::Tag.find_or_create_with_like_by_name(title)
    taggings = contact_taggings(tag)
    current = taggings.pluck(:taggable_id)
    wanted = contact_ids.uniq

    taggings.where(taggable_id: current - wanted).delete_all
    rows = (wanted - current).map do |id|
      { tag_id: tag.id, taggable_type: 'Contact', taggable_id: id, context: 'labels', created_at: Time.current }
    end
    ActsAsTaggableOn::Tagging.insert_all(rows) if rows.any? # rubocop:disable Rails/SkipsModelValidations
  end

  # A list taken out of the integration stops being mirrored, so its label is cleared rather
  # than left behind as an audience nobody keeps up to date.
  def release_dropped_lists(labels)
    (labels.keys - list_ids).each do |list_id|
      tag = ActsAsTaggableOn::Tag.find_by(name: labels.delete(list_id))
      contact_taggings(tag).delete_all if tag.present?
    end
  end

  def contact_taggings(tag)
    ActsAsTaggableOn::Tagging.where(tag_id: tag.id, taggable_type: 'Contact', context: 'labels', taggable_id: @account.contacts.select(:id))
  end
end
