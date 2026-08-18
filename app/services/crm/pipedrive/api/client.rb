class Crm::Pipedrive::Api::Client
  include HTTParty
  base_uri 'https://api.pipedrive.com'

  PAGE_SIZE = 100

  class ApiError < StandardError; end

  def initialize(api_token)
    @api_token = api_token
  end

  def pipeline(pipeline_id)
    request(:get, "/v1/pipelines/#{pipeline_id}")
  end

  def stages(pipeline_id)
    request(:get, '/v1/stages', query: { pipeline_id: pipeline_id })
  end

  def users
    request(:get, '/v1/users')
  end

  def person(person_id)
    request(:get, "/v1/persons/#{person_id}")
  end

  def deals(pipeline_id:, updated_since:)
    paginated('/api/v2/deals', pipeline_id: pipeline_id, updated_since: updated_since)
  end

  def activities(updated_since:)
    paginated('/api/v2/activities', updated_since: updated_since)
  end

  # Field dictionary: custom fields arrive keyed by hash, this maps them to their names.
  def deal_fields
    request(:get, '/v1/dealFields', query: { limit: 500 })
  end

  def deal(deal_id)
    request(:get, "/api/v2/deals/#{deal_id}")
  end

  # v1 carries stay_in_pipeline_stages, which powers the stage progress bar.
  def deal_detail(deal_id)
    request(:get, "/v1/deals/#{deal_id}")
  end

  def deal_changelog(deal_id)
    request(:get, "/v1/deals/#{deal_id}/changelog", query: { limit: 30 })
  end

  def activity_types
    request(:get, '/v1/activityTypes')
  end

  def deal_products(deal_id)
    request(:get, "/v1/deals/#{deal_id}/products", query: { limit: 100 })
  end

  def deal_files(deal_id)
    request(:get, "/v1/deals/#{deal_id}/files", query: { limit: 100 })
  end

  def deal_notes(deal_id)
    request(:get, '/v1/notes', query: { deal_id: deal_id, limit: 50, sort: 'add_time DESC' })
  end

  def deal_activities(deal_id)
    request(:get, "/v1/deals/#{deal_id}/activities", query: { limit: 50 })
  end

  # Files live behind the API, so they are streamed through Chatwoot instead of linked.
  def download_file(file_id)
    response = self.class.get("/v1/files/#{file_id}/download", headers: headers)
    raise ApiError, "Pipedrive file #{file_id} download failed (#{response.code})" unless response.success?

    response
  end

  def create_webhook(subscription_url:, event_object:, auth_user:, auth_password:)
    request(:post, '/v1/webhooks', body: {
              subscription_url: subscription_url,
              event_action: '*',
              event_object: event_object,
              version: '2.0',
              http_auth_user: auth_user,
              http_auth_password: auth_password
            })
  end

  def delete_webhook(webhook_id)
    request(:delete, "/v1/webhooks/#{webhook_id}")
  end

  private

  def paginated(path, query)
    records = []
    cursor = nil

    loop do
      response = full_response(:get, path, query: query.merge(limit: PAGE_SIZE, cursor: cursor).compact)
      records.concat(Array(response['data']))
      cursor = response.dig('additional_data', 'next_cursor')
      break if cursor.blank?
    end

    records
  end

  def request(method, path, query: {}, body: nil)
    full_response(method, path, query: query, body: body)['data']
  end

  def full_response(method, path, query: {}, body: nil)
    options = { headers: headers, query: query }
    options[:body] = body.to_json if body.present?

    response = self.class.public_send(method, path, options)
    raise ApiError, "Pipedrive #{method.to_s.upcase} #{path} failed (#{response.code}): #{response.body}" unless response.success?

    response.parsed_response
  end

  def headers
    { 'x-api-token' => @api_token, 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
  end
end
