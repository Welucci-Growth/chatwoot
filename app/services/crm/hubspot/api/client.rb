class Crm::Hubspot::Api::Client
  include HTTParty
  base_uri 'https://api.hubapi.com'

  PAGE_SIZE = 100
  DEAL_PROPERTIES = %w[
    dealname dealstage pipeline amount closedate createdate hs_lastmodifieddate
    hubspot_owner_id dealtype description hs_deal_stage_probability
    hs_is_closed_won closed_lost_reason
  ].freeze

  class ApiError < StandardError; end

  def initialize(access_token)
    @access_token = access_token
  end

  def pipelines
    request(:get, '/crm/v3/pipelines/deals')['results'] || []
  end

  def owners
    paginated('/crm/v3/owners')
  end

  def deal(deal_id)
    request(:get, "/crm/v3/objects/deals/#{deal_id}", query: { properties: DEAL_PROPERTIES.join(',') })
  end

  # HubSpot has no webhook we can register from a private app, so the mirror asks what
  # changed since the last run. The search endpoint filters server-side by pipeline and
  # modification time, which keeps each sync proportional to the changes, not the CRM size.
  # Custom properties are only returned when named explicitly, so the caller passes the
  # keys it cares about; without them the cards would carry no CRM fields at all.
  def deals_changed_since(pipeline_id:, since:, extra_properties: [])
    search('/crm/v3/objects/deals/search',
           properties: (DEAL_PROPERTIES + Array(extra_properties)).uniq,
           filters: [
             { propertyName: 'pipeline', operator: 'EQ', value: pipeline_id },
             { propertyName: 'hs_lastmodifieddate', operator: 'GTE', value: (since.to_f * 1000).round }
           ])
  end

  def contacts_for_deal(deal_id)
    body = request(:get, "/crm/v4/objects/deals/#{deal_id}/associations/contacts")
    Array(body['results']).filter_map { |r| r['toObjectId'] }
  end

  def contact(contact_id)
    request(:get, "/crm/v3/objects/contacts/#{contact_id}",
            query: { properties: 'email,phone,firstname,lastname' })
  end

  def deal_properties
    request(:get, '/crm/v3/properties/deals')['results'] || []
  end

  private

  def search(path, filters:, properties: DEAL_PROPERTIES)
    results = []
    after = nil

    loop do
      body = {
        filterGroups: [{ filters: filters }],
        properties: properties,
        limit: PAGE_SIZE
      }
      body[:after] = after if after.present?

      page = request(:post, path, body: body.to_json)
      results.concat(page['results'] || [])
      after = page.dig('paging', 'next', 'after')
      break if after.blank?
    end

    results
  end

  def paginated(path)
    results = []
    after = nil

    loop do
      query = { limit: PAGE_SIZE }
      query[:after] = after if after.present?
      page = request(:get, path, query: query)
      results.concat(page['results'] || [])
      after = page.dig('paging', 'next', 'after')
      break if after.blank?
    end

    results
  end

  def request(method, path, options = {})
    response = self.class.public_send(method, path, options.merge(headers: headers, timeout: 60))
    raise ApiError, "HubSpot #{method.to_s.upcase} #{path}: #{response.code} #{response.body.to_s.first(200)}" unless response.success?

    response.parsed_response
  end

  def headers
    { 'Authorization' => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
  end
end
