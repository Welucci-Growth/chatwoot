class Crm::Pipedrive::DealPanelService
  DEAL_ENDPOINTS = %i[deal_detail deal_products deal_files deal_notes deal_activities deal_changelog].freeze

  IMAGE_TYPES = %w[img jpg jpeg png gif webp heic].freeze

  STANDARD_FIELD_LABELS = {
    'title' => 'Título', 'value' => 'Valor', 'stage_id' => 'Etapa', 'status' => 'Status',
    'expected_close_date' => 'Previsão de fechamento', 'owner_id' => 'Responsável',
    'person_id' => 'Contato', 'org_id' => 'Organização', 'probability' => 'Probabilidade'
  }.freeze

  def initialize(task)
    @task = task
    @crm = task.custom_attributes['pipedrive'] || {}
    @hook = task.account.hooks.find_by!(app_id: 'pipedrive')
  end

  # Related records are read live when the panel opens: mirroring them would mean several
  # extra API calls on every webhook and data that goes stale between events.
  def perform
    build_panel(fetch_in_parallel(fetchers))
  end

  private

  def fetchers
    by_deal = DEAL_ENDPOINTS.to_h do |endpoint|
      [endpoint.to_s.delete_prefix('deal_').to_sym, -> { client.public_send(endpoint, deal_id) }]
    end

    by_deal.merge(person: -> { person_id.present? ? client.person(person_id) : nil })
  end

  def build_panel(data)
    {
      stages: stage_progress(data[:detail]),
      counters: counters(data),
      products: products(data[:products]),
      files: files(data[:files]),
      notes: notes(data[:notes]),
      activities: activities(data[:activities]),
      changelog: changelog(data[:changelog]),
      person: person(data[:person])
    }
  end

  def deal_id
    @crm['deal_id']
  end

  def person_id
    @crm['person_id']
  end

  def client
    @client ||= Crm::Pipedrive::Api::Client.new(@hook.settings['api_token'])
  end

  # Seven sequential calls would keep the panel waiting for two seconds.
  def fetch_in_parallel(fetchers)
    fetchers.transform_values { |fetcher| Thread.new { Rails.application.executor.wrap { fetcher.call } } }
            .transform_values(&:value)
  end

  def counters(data)
    {
      products: Array(data[:products]).size,
      files: Array(data[:files]).size,
      notes: Array(data[:notes]).size,
      activities: Array(data[:activities]).size
    }
  end

  # Mirrors the stage bar of the CRM: every stage of the pipeline, the days the deal spent
  # there and where it stands now.
  def stage_progress(detail)
    times = detail.dig('stay_in_pipeline_stages', 'times_in_stages') || {}
    columns = @task.task_board.task_columns.index_by(&:id)
    stage_columns = @hook.settings['stage_columns'] || {}

    ordered_stage_ids(detail).filter_map do |stage_id|
      name = columns[stage_columns[stage_id.to_s]]&.name
      next if name.blank?

      { name: name, days: times[stage_id.to_s].to_i / 1.day.to_i, current: stage_id.to_s == @crm['stage_id'].to_s }
    end
  end

  def ordered_stage_ids(detail)
    order = detail.dig('stay_in_pipeline_stages', 'order_of_stages')
    return order.sort_by { |_stage_id, position| position }.map(&:first) if order.is_a?(Hash)

    Array(order)
  end

  def products(records)
    Array(records).map do |product|
      {
        name: product['name'],
        quantity: product['quantity'],
        price: product['item_price'],
        sum: product['sum'],
        currency: product['currency'],
        comments: product['comments'].presence
      }
    end
  end

  def files(records)
    Array(records).map do |file|
      {
        id: file['id'],
        name: file['name'],
        size: file['file_size'],
        image: image?(file),
        added_at: file['add_time']
      }
    end
  end

  # Pipedrive tags images as 'img' rather than by extension, and some uploads arrive with
  # no type at all, so the file name is the fallback.
  def image?(file)
    return true if IMAGE_TYPES.include?(file['file_type'].to_s.downcase)

    IMAGE_TYPES.include?(File.extname(file['name'].to_s).delete('.').downcase)
  end

  def notes(records)
    Array(records).map do |note|
      {
        id: note['id'],
        content: to_text(note['content']),
        author: note.dig('user', 'name'),
        added_at: note['add_time']
      }
    end
  end

  def activities(records)
    Array(records).map do |activity|
      {
        id: activity['id'],
        subject: activity['subject'],
        type: activity_type_label(activity['type']),
        done: activity['done'],
        due_date: activity['due_date'],
        due_time: activity['due_time'],
        done_at: activity['marked_as_done_time'],
        owner: activity['owner_name'],
        note: to_text(activity['note'])
      }
    end
  end

  def changelog(records)
    Array(records).filter_map do |entry|
      label = field_label(entry['field_key'])
      next if label.blank?

      { field: label, from: entry['old_value'], to: entry['new_value'], changed_at: entry['log_time'] }
    end
  end

  # Custom fields arrive keyed by hash; the dictionary stored at setup gives them a name.
  def field_label(key)
    return STANDARD_FIELD_LABELS[key] if STANDARD_FIELD_LABELS.key?(key)

    Array(@hook.settings['deal_fields']).find { |field| field['key'] == key }&.dig('name')
  end

  def activity_type_label(type)
    (@hook.settings['activity_types'] || {})[type] || type
  end

  def person(data)
    return nil if data.blank?

    {
      name: data['name'],
      emails: Array(data['email']).filter_map { |entry| entry['value'].presence },
      phones: Array(data['phone']).filter_map { |entry| entry['value'].presence },
      organization: data.dig('org_id', 'name')
    }
  end

  def to_text(value)
    return nil if value.blank?

    ActionView::Base.full_sanitizer.sanitize(value.gsub(%r{<br\s*/?>|</p>}i, "\n")).strip.presence
  end
end
