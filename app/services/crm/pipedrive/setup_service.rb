class Crm::Pipedrive::SetupService
  ACTIVITIES_BOARD_NAME = 'Pipedrive · Atividades'.freeze
  ACTIVITIES_BOARD_COLUMNS = ['A fazer', 'Concluídas'].freeze
  BOARD_NAME_PREFIX = 'Pipedrive · '.freeze
  WEBHOOK_USER = 'chatwoot'.freeze

  def initialize(hook)
    @hook = hook
    @account = hook.account
  end

  # Provisions the boards that mirror Pipedrive and subscribes to the CRM webhooks.
  # Runs on hook creation and whenever the integration settings change.
  def setup
    remove_webhooks
    provision_boards
    map_users
    map_deal_fields
    map_activity_types
    register_webhooks
    @hook.save!
  end

  def teardown
    remove_webhooks
  end

  private

  def settings
    @hook.settings
  end

  def client
    @client ||= Crm::Pipedrive::Api::Client.new(settings['api_token'])
  end

  def pipeline_ids
    settings['pipeline_ids'].to_s.split(',').filter_map { |id| id.strip.presence }
  end

  def sync_activities?
    ActiveModel::Type::Boolean.new.cast(settings['sync_activities']).present?
  end

  def provision_boards
    boards = {}
    stage_columns = {}

    boards['activities'] = find_or_create_board(ACTIVITIES_BOARD_NAME, ACTIVITIES_BOARD_COLUMNS).id if sync_activities?

    pipeline_ids.each do |pipeline_id|
      board, stages = provision_pipeline_board(pipeline_id)
      boards[pipeline_id] = board.id
      stages.each { |stage| stage_columns[stage['id'].to_s] = board.task_columns.find_by(name: stage['name']).id }
    end

    settings['board_ids'] = boards
    settings['stage_columns'] = stage_columns
  end

  def provision_pipeline_board(pipeline_id)
    pipeline = client.pipeline(pipeline_id)
    stages = client.stages(pipeline_id).sort_by { |stage| stage['order_nr'] }

    [find_or_create_board("#{BOARD_NAME_PREFIX}#{pipeline['name']}", stages.pluck('name')), stages]
  end

  # The board mirrors the pipeline, so columns follow the CRM stages and their order.
  def find_or_create_board(name, column_names)
    board = @account.task_boards.find_or_create_by!(name: name) { |new_board| new_board.visibility = :shared }

    column_names.each_with_index do |column_name, index|
      column = board.task_columns.find_by(name: column_name)
      column.present? ? column.update!(position: index) : board.task_columns.create!(name: column_name, position: index)
    end

    board.reload
  end

  # Cards land on the Chatwoot agent that shares the Pipedrive user's email.
  def map_users
    agent_ids_by_email = @account.users.pluck(:email, :id).to_h
    settings['user_map'] = client.users.each_with_object({}) do |user, map|
      agent_id = agent_ids_by_email[user['email'].to_s.downcase]
      map[user['id'].to_s] = agent_id if agent_id.present?
    end
  end

  # Custom fields come keyed by a hash and mostly empty. We keep the dictionary (name,
  # type, order and option labels) so the cards can render the filled ones by name.
  def map_deal_fields
    settings['deal_fields'] = client.deal_fields.filter_map do |field|
      next unless custom_field?(field)

      {
        'key' => field['key'],
        'name' => field['name'],
        'type' => field['field_type'],
        'order' => field['order_nr'],
        'options' => Array(field['options']).to_h { |option| [option['id'].to_s, option['label']] }.presence
      }.compact
    end
  end

  # Pipedrive keys its custom fields with a 40 character hash; built in ones use plain names.
  def custom_field?(field)
    field['key'].to_s.length == 40
  end

  def map_activity_types
    settings['activity_types'] = client.activity_types.to_h { |type| [type['key_string'], type['name']] }
  end

  def register_webhooks
    secret = settings['webhook_secret'].presence || SecureRandom.hex(24)
    settings['webhook_secret'] = secret

    objects = []
    objects << 'deal' if pipeline_ids.any?
    objects << 'activity' if sync_activities?

    settings['webhook_ids'] = objects.map do |event_object|
      client.create_webhook(
        subscription_url: subscription_url,
        event_object: event_object,
        auth_user: WEBHOOK_USER,
        auth_password: secret
      )['id']
    end
  end

  def remove_webhooks
    Array(settings['webhook_ids']).each { |webhook_id| client.delete_webhook(webhook_id) }
    settings['webhook_ids'] = []
  end

  def subscription_url
    "#{ENV.fetch('FRONTEND_URL')}/webhooks/pipedrive/#{@hook.id}"
  end
end
