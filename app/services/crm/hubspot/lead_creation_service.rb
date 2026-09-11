# The sales team works out of the Leads board, so someone who reaches out on Instagram only
# becomes visible to them once a lead exists there. Created at most once per conversation:
# the lead id is kept on the conversation, and a second call returns it instead of a twin.
class Crm::Hubspot::LeadCreationService
  def initialize(conversation)
    @conversation = conversation
    @account = conversation.account
    @settings = LuciSetting.for_account(@account)
    @hook = @account.hooks.find_by!(app_id: 'hubspot')
  end

  def perform
    return { status: 'nao_configurado' } if destination.blank?
    return { status: 'ja_existe', lead_id: existing_lead_id } if existing_lead_id.present?

    lead = client.create_lead(properties: lead_properties, contact_id: hubspot_contact_id)
    remember(lead['id'])
    { status: 'criado', lead_id: lead['id'] }
  end

  private

  def destination
    ids = [@settings.lead_pipeline_id, @settings.lead_stage_id]
    ids.all?(&:present?) ? ids : nil
  end

  def existing_lead_id
    @conversation.custom_attributes['hubspot_lead_id']
  end

  def remember(lead_id)
    @conversation.update!(
      custom_attributes: @conversation.custom_attributes.merge('hubspot_lead_id' => lead_id.to_s)
    )
  end

  def lead_properties
    pipeline_id, stage_id = destination

    {
      hs_lead_name: contact.name.presence || "Lead #{@conversation.display_id}",
      hs_pipeline: pipeline_id,
      hs_pipeline_stage: stage_id,
      hs_lead_type: 'NEW_BUSINESS'
    }
  end

  # The HubSpot id is cached on the Chatwoot contact, so a client who comes back tomorrow
  # attaches to the same person instead of spawning a duplicate.
  def hubspot_contact_id
    cached = contact.additional_attributes.dig('external', 'hubspot_id')
    return cached if cached.present?

    record = matching_contact || client.create_contact(contact_properties)
    contact.additional_attributes = contact.additional_attributes.deep_merge(
      'external' => { 'hubspot_id' => record['id'].to_s }
    )
    contact.save!
    record['id']
  end

  # Instagram gives us neither email nor phone, so most of these are new people in HubSpot.
  # Where Chatwoot does hold one, it is what keeps the CRM from gaining a second copy.
  def matching_contact
    return client.find_contact('email', contact.email) if contact.email.present?
    return client.find_contact('phone', contact.phone_number) if contact.phone_number.present?

    nil
  end

  def contact_properties
    names = contact.name.to_s.split

    {
      firstname: names.first,
      lastname: names.drop(1).join(' '),
      email: contact.email,
      phone: contact.phone_number
    }.compact_blank
  end

  def contact
    @contact ||= @conversation.contact
  end

  def client
    @client ||= Crm::Hubspot::Api::Client.new(@hook.settings['access_token'])
  end
end
