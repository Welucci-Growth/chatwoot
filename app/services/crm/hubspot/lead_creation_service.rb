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
    # The id we stored is not proof the card is still there: a lead can be deleted or
    # discarded inside HubSpot afterwards, and trusting the id would leave the client with no
    # lead at all — silently, and precisely when someone is waiting to be served.
    return { status: 'ja_existe', lead_id: existing_lead_id } if still_on_the_board?

    contact_id = hubspot_contact_id
    known = client.contact_lead_id(contact_id)
    if known.present?
      remember(known)
      return { status: 'ja_no_hubspot', lead_id: known }
    end

    lead = client.create_lead(properties: lead_properties, contact_id: contact_id)
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

  def still_on_the_board?
    existing_lead_id.present? && client.lead_exists?(existing_lead_id)
  end

  def remember(lead_id)
    @conversation.update!(
      custom_attributes: @conversation.custom_attributes.merge('hubspot_lead_id' => lead_id.to_s)
    )
  end

  def lead_properties
    pipeline_id, stage_id = destination

    {
      hs_lead_name: lead_name,
      hs_pipeline: pipeline_id,
      hs_pipeline_stage: stage_id,
      hs_lead_type: 'NEW_BUSINESS',
      origem: origin
    }.compact_blank
  end

  # An SDR opening this card needs to reach the person on Instagram, and the display name
  # ("Kauã") is neither unique nor searchable there — the handle is.
  def lead_name
    return "@#{handle}" if handle.present?

    contact.name.presence || "Lead #{@conversation.display_id}"
  end

  def handle
    attributes = contact.additional_attributes
    attributes['social_instagram_user_name'].presence || attributes.dig('social_profiles', 'instagram')
  end

  # "Instagram" is already one of the values the team uses in this field, so the card joins
  # their reporting instead of creating a spelling of its own.
  def origin
    case @conversation.inbox.channel_type
    when 'Channel::Instagram' then 'Instagram'
    when 'Channel::Whatsapp' then 'WhatsApp'
    end
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
