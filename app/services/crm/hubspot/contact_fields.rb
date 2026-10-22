# The HubSpot properties the team segments by, kept on each contact as custom attributes so
# Chatwoot's own contact filters and saved segments can use them. HubSpot is the source of
# truth for these: every sync overwrites them.
class Crm::Hubspot::ContactFields
  OWNER_PROPERTY = 'hubspot_owner_id'.freeze
  FIELDS = [
    { property: 'lifecyclestage', key: 'hubspot_etapa', name: 'Etapa do ciclo de vida (HubSpot)' },
    { property: 'hs_lead_status', key: 'hubspot_status_lead', name: 'Status do lead (HubSpot)' },
    { property: OWNER_PROPERTY, key: 'hubspot_vendedor', name: 'Vendedor (HubSpot)' },
    { property: 'hs_analytics_source', key: 'hubspot_origem', name: 'Origem (HubSpot)' },
    { property: 'origem', key: 'hubspot_origem_welucci', name: 'Origem Welucci (HubSpot)' },
    { property: 'city', key: 'hubspot_cidade', name: 'Cidade (HubSpot)' },
    { property: 'state', key: 'hubspot_estado', name: 'Estado (HubSpot)' },
    { property: 'company', key: 'hubspot_empresa', name: 'Empresa (HubSpot)' }
  ].freeze

  def initialize(account, client)
    @account = account
    @client = client
  end

  # Reads the properties from HubSpot and keeps the attribute definitions in step with them,
  # so a new stage or owner shows up as a filter option on the next sync.
  def sync_definitions!
    @fields = FIELDS.filter_map { |field| resolve(field) }
    @fields.each { |field| save_definition(field) }
    self
  end

  def properties
    @fields.pluck(:property)
  end

  def custom_attributes_for(props)
    @fields.to_h do |field|
      raw = props[field[:property]].presence
      [field[:key], raw && (field[:options]&.fetch(raw.to_s, nil) || raw.to_s)]
    end
  end

  private

  def resolve(field)
    return field.merge(options: owner_names) if field[:property] == OWNER_PROPERTY

    property = @client.contact_property(field[:property])
    return nil if property.blank?

    options = Array(property['options']).to_h { |option| [option['value'].to_s, option['label'].to_s] }
    field.merge(options: options.presence)
  end

  def owner_names
    @client.owners.to_h do |owner|
      name = [owner['firstName'], owner['lastName']].compact_blank.join(' ').presence || owner['email']
      [owner['id'].to_s, name.to_s]
    end
  end

  def save_definition(field)
    definition = @account.custom_attribute_definitions.find_or_initialize_by(attribute_key: field[:key], attribute_model: :contact_attribute)
    definition.attribute_display_name = field[:name]
    definition.attribute_description = "Vem do HubSpot (#{field[:property]}) e é atualizado a cada sincronização."
    definition.attribute_display_type = field[:options] ? :list : :text
    definition.attribute_values = field[:options]&.values&.uniq || []
    definition.save! if definition.changed?
  end
end
