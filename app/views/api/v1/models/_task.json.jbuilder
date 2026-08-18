json.id resource.id
json.title resource.title
json.description resource.description
json.position resource.position
json.task_board_id resource.task_board_id
json.task_column_id resource.task_column_id
json.due_on resource.due_on&.to_i
json.overdue resource.overdue?
json.conversation_id resource.conversation_id
json.labels resource.label_list
json.custom_attributes resource.custom_attributes
if resource.assignee.present?
  json.assignee do
    json.partial! 'api/v1/models/agent', formats: [:json], resource: resource.assignee
  end
end
if resource.contact.present?
  json.contact do
    json.id resource.contact.id
    json.name resource.contact.name
    json.thumbnail resource.contact.avatar_url
  end
end
json.created_at resource.created_at.to_i
json.updated_at resource.updated_at.to_i
