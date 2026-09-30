class Crm::Hubspot::Api::Client
  include HTTParty
  base_uri 'https://api.hubapi.com'

  PAGE_SIZE = 100
  BATCH_SIZE = 100
  # Well under HubSpot's 19 requests per second, leaving room for the rest of the app.
  MAX_PER_SECOND = 8
  DEAL_PROPERTIES = %w[
    dealname dealstage pipeline amount closedate createdate hs_lastmodifieddate
    hubspot_owner_id dealtype description hs_deal_stage_probability
    hs_is_closed_won closed_lost_reason
  ].freeze

  CONTACT_PROPERTIES = %w[email phone firstname lastname].freeze
  # HubSpot's own "Primary" association between a lead and the contact behind it.
  LEAD_CONTACT_PRIMARY = 578

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

  # Asking per deal would cost one request each — over thirteen thousand for a single
  # pipeline, which would exhaust HubSpot's 190-per-10-seconds budget. The batch endpoints
  # take a hundred at a time and bring the same work down to a few dozen calls.
  def deal_contact_ids(deal_ids)
    return {} if deal_ids.blank?

    deal_ids.each_slice(BATCH_SIZE).with_object({}) do |slice, index|
      body = request(:post, '/crm/v4/associations/deals/contacts/batch/read',
                     body: { inputs: slice.map { |id| { id: id.to_s } } }.to_json)
      Array(body['results']).each do |result|
        contact_id = Array(result['to']).first&.dig('toObjectId')
        index[result.dig('from', 'id').to_s] = contact_id if contact_id.present?
      end
    end
  end

  def contacts(contact_ids)
    return {} if contact_ids.blank?

    contact_ids.uniq.each_slice(BATCH_SIZE).with_object({}) do |slice, index|
      body = request(:post, '/crm/v3/objects/contacts/batch/read',
                     body: { inputs: slice.map { |id| { id: id.to_s } },
                             properties: CONTACT_PROPERTIES }.to_json)
      Array(body['results']).each { |contact| index[contact['id'].to_s] = contact }
    end
  end

  def deal_properties
    request(:get, '/crm/v3/properties/deals')['results'] || []
  end

  # A lead only exists attached to a contact, so the association travels in the same call
  # that creates it — HubSpot rejects a lead that reaches it on its own.
  def create_lead(properties:, contact_id:)
    request(:post, '/crm/v3/objects/leads',
            body: { properties: properties,
                    associations: [{ to: { id: contact_id.to_s },
                                     types: [{ associationCategory: 'HUBSPOT_DEFINED',
                                               associationTypeId: LEAD_CONTACT_PRIMARY }] }] }.to_json)
  end

  # An id we stored is not proof the record is still there: HubSpot deletes and merges records
  # on its own, and both leave the old id pointing at nothing.
  def lead_exists?(lead_id)
    record_exists?("/crm/v3/objects/leads/#{lead_id}")
  end

  def contact_exists?(contact_id)
    record_exists?("/crm/v3/objects/contacts/#{contact_id}")
  end

  # HubSpot itself creates a lead for everyone who arrives through an ad, so the contact is
  # asked first — otherwise the same person would end up on the board twice.
  def contact_lead_id(contact_id)
    body = request(:get, "/crm/v4/objects/contacts/#{contact_id}/associations/leads")
    Array(body['results']).first&.dig('toObjectId')
  end

  def create_contact(properties)
    request(:post, '/crm/v3/objects/contacts', body: { properties: properties }.to_json)
  end

  def find_contact(property, value)
    search('/crm/v3/objects/contacts/search',
           properties: CONTACT_PROPERTIES,
           filters: [{ propertyName: property, operator: 'EQ', value: value }]).first
  end

  private

  # Asked by id rather than through search: HubSpot's search index trails creation by minutes,
  # so a record created moments ago reads as missing there — and would be created twice.
  def record_exists?(path)
    throttle
    response = self.class.get(path, headers: headers, timeout: 60)
    return false if response.code == 404
    raise ApiError, "HubSpot GET #{path}: #{response.code}" unless response.success?

    true
  end

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
    throttle
    response = self.class.public_send(method, path, options.merge(headers: headers, timeout: 60))
    raise ApiError, "HubSpot #{method.to_s.upcase} #{path}: #{response.code} #{response.body.to_s.first(200)}" unless response.success?

    response.parsed_response
  end

  def headers
    { 'Authorization' => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
  end

  # Paces the client so a large import never becomes a burst. HubSpot answers 429 when the
  # budget runs out, and that budget is shared with everything else the account does.
  def throttle
    @request_times ||= []
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @request_times.reject! { |t| now - t > 1.0 }
    if @request_times.size >= MAX_PER_SECOND
      sleep(1.0 - (now - @request_times.first))
      @request_times.clear
    end
    @request_times << Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
