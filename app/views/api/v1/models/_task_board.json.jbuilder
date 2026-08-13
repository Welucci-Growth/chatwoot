json.id resource.id
json.name resource.name
json.visibility resource.visibility
json.position resource.position
json.owner_id resource.owner_id
if resource.owner.present?
  json.owner do
    json.partial! 'api/v1/models/agent', formats: [:json], resource: resource.owner
  end
end
json.created_at resource.created_at.to_i
json.updated_at resource.updated_at.to_i
