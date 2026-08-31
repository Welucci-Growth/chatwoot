class Crm::Hubspot::SetupService
  BOARD_NAME_PREFIX = 'HubSpot · '.freeze

  def initialize(hook)
    @hook = hook
    @account = hook.account
  end

  # Provisions the boards that mirror HubSpot. Unlike Pipedrive there are no webhooks to
  # register: a private app token cannot subscribe to them, so a scheduled sync pulls
  # what changed instead.
  def setup
    provision_boards
    map_owners
    map_deal_properties
    @hook.save!
  end

  def teardown
    # Nothing is registered on HubSpot's side, so there is nothing to undo there.
    true
  end

  private

  def settings
    @hook.settings
  end

  def client
    @client ||= Crm::Hubspot::Api::Client.new(settings['access_token'])
  end

  def pipeline_ids
    settings['pipeline_ids'].to_s.split(',').filter_map { |id| id.strip.presence }
  end

  def provision_boards
    available = client.pipelines.index_by { |p| p['id'].to_s }
    boards = {}
    stage_columns = {}

    pipeline_ids.each do |pipeline_id|
      pipeline = available[pipeline_id]
      next if pipeline.blank?

      board, stages = provision_pipeline_board(pipeline)
      boards[pipeline_id] = board.id
      stage_columns.merge!(columns_for(board, stages))
    end

    settings['board_ids'] = boards
    settings['stage_columns'] = stage_columns
  end

  def provision_pipeline_board(pipeline)
    stages = Array(pipeline['stages']).sort_by { |stage| stage['displayOrder'].to_i }
    [find_or_create_board("#{BOARD_NAME_PREFIX}#{pipeline['label']}", stages.pluck('label')), stages]
  end

  def columns_for(board, stages)
    stages.to_h { |stage| [stage['id'].to_s, board.task_columns.find_by(name: stage['label']).id] }
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

  # Cards land on the Chatwoot agent that shares the HubSpot owner's email.
  def map_owners
    agent_ids_by_email = @account.users.pluck(:email, :id).to_h.transform_keys { |email| email.to_s.downcase }
    settings['owner_map'] = client.owners.each_with_object({}) do |owner, map|
      agent_id = agent_ids_by_email[owner['email'].to_s.downcase]
      map[owner['id'].to_s] = agent_id if agent_id.present?
    end
  end

  # Keeps the dictionary of custom properties so cards can show the filled ones by label
  # instead of by internal name.
  def map_deal_properties
    settings['deal_fields'] = client.deal_properties.filter_map do |field|
      next if field['hubspotDefined']

      {
        'key' => field['name'],
        'name' => field['label'],
        'order' => field['displayOrder'],
        'options' => Array(field['options']).to_h { |o| [o['value'].to_s, o['label']] }.presence
      }.compact
    end
  end
end
