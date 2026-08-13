json.partial! 'api/v1/models/task_board', formats: [:json], resource: resource
json.columns resource.task_columns do |column|
  json.partial! 'api/v1/models/task_column', formats: [:json], resource: column
  json.tasks column.tasks do |task|
    json.partial! 'api/v1/models/task', formats: [:json], resource: task
  end
end
