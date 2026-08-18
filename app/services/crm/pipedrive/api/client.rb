class Crm::Pipedrive::Api::Client
  include HTTParty
  base_uri 'https://api.pipedrive.com/v1'

  class ApiError < StandardError; end

  def initialize(api_token)
    @api_token = api_token
  end

  def pipeline(pipeline_id)
    request(:get, "/pipelines/#{pipeline_id}")
  end

  def stages(pipeline_id)
    request(:get, '/stages', query: { pipeline_id: pipeline_id })
  end

  def users
    request(:get, '/users')
  end

  def person(person_id)
    request(:get, "/persons/#{person_id}")
  end

  def create_webhook(subscription_url:, event_object:, auth_user:, auth_password:)
    request(:post, '/webhooks', body: {
              subscription_url: subscription_url,
              event_action: '*',
              event_object: event_object,
              version: '2.0',
              http_auth_user: auth_user,
              http_auth_password: auth_password
            })
  end

  def delete_webhook(webhook_id)
    request(:delete, "/webhooks/#{webhook_id}")
  end

  private

  def request(method, path, query: {}, body: nil)
    options = { headers: headers, query: query }
    options[:body] = body.to_json if body.present?

    response = self.class.public_send(method, path, options)
    raise ApiError, "Pipedrive #{method.to_s.upcase} #{path} failed (#{response.code}): #{response.body}" unless response.success?

    response.parsed_response['data']
  end

  def headers
    { 'x-api-token' => @api_token, 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
  end
end
