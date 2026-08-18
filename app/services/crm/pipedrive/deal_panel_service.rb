class Crm::Pipedrive::DealPanelService
  # Pipedrive tags images as 'img' rather than by extension, and some uploads arrive with
  # no type at all, so the file name is the fallback.
  IMAGE_TYPES = %w[img jpg jpeg png gif webp heic].freeze

  def initialize(task)
    @task = task
    @crm = task.custom_attributes['pipedrive'] || {}
    @hook = task.account.hooks.find_by!(app_id: 'pipedrive')
  end

  # Related records are read live when the panel opens: storing them would mean four extra
  # API calls on every webhook and data that goes stale between events.
  def perform
    {
      products: products,
      files: files,
      notes: notes,
      activities: activities,
      person: person
    }
  end

  private

  def deal_id
    @crm['deal_id']
  end

  def client
    @client ||= Crm::Pipedrive::Api::Client.new(@hook.settings['api_token'])
  end

  def products
    Array(client.deal_products(deal_id)).map do |product|
      {
        name: product['name'],
        quantity: product['quantity'],
        price: product['item_price'],
        discount: product['discount'],
        sum: product['sum'],
        currency: product['currency'],
        comments: product['comments'].presence
      }
    end
  end

  def files
    Array(client.deal_files(deal_id)).map do |file|
      {
        id: file['id'],
        name: file['name'],
        size: file['file_size'],
        type: file['file_type'],
        image: image?(file),
        added_at: file['add_time'],
        remote_url: file['url'].presence
      }
    end
  end

  def image?(file)
    return true if IMAGE_TYPES.include?(file['file_type'].to_s.downcase)

    IMAGE_TYPES.include?(File.extname(file['name'].to_s).delete('.').downcase)
  end

  def notes
    Array(client.deal_notes(deal_id)).map do |note|
      {
        id: note['id'],
        content: to_text(note['content']),
        author: note.dig('user', 'name'),
        added_at: note['add_time']
      }
    end
  end

  def activities
    Array(client.deal_activities(deal_id)).map do |activity|
      {
        id: activity['id'],
        subject: activity['subject'],
        type: activity['type'],
        done: activity['done'],
        due_date: activity['due_date'],
        due_time: activity['due_time'],
        owner: activity['owner_name'],
        note: to_text(activity['note'])
      }
    end
  end

  def person
    person_id = @crm['person_id']
    return nil if person_id.blank?

    data = client.person(person_id)
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
