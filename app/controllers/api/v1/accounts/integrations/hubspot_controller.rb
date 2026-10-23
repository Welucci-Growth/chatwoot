class Api::V1::Accounts::Integrations::HubspotController < Api::V1::Accounts::Integrations::BaseController
  before_action :check_authorization
  before_action :fetch_hook

  def segments
    chosen = @hook.settings['contact_list_ids'].to_s.split(',').map(&:strip)
    segments = Crm::Hubspot::Api::Client.new(@hook.settings['access_token']).contact_segments.map do |segment|
      id = segment['listId'].to_s
      { id: id, name: segment['name'], size: segment.dig('additionalProperties', 'hs_list_size').to_i,
        dynamic: segment['processingType'] == 'DYNAMIC', selected: chosen.include?(id) }
    end
    render json: { segments: segments }
  rescue Crm::Hubspot::Api::Client::ApiError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # The segment ids are a config key of the hook, so saving them runs its setup, which mirrors
  # the chosen segments as labels straight away instead of waiting for the hourly sync.
  def update_segments
    @hook.merge_settings!('contact_list_ids' => Array(params[:segment_ids]).map(&:to_s).join(','))
    head :ok
  end

  private

  def check_authorization
    authorize(:hook, :update?)
  end

  def fetch_hook
    @hook = Current.account.hooks.find_by!(app_id: 'hubspot')
  end
end
