namespace :pipedrive do
  # bundle exec rake 'pipedrive:backfill[1,2026-08-01]'
  desc 'Import Pipedrive records changed since a date into the Tasks boards'
  task :backfill, [:account_id, :since] => :environment do |_task, args|
    hook = Integrations::Hook.find_by!(account_id: args[:account_id], app_id: 'pipedrive')
    updated_since = Time.zone.parse(args[:since]).utc.iso8601

    Crm::Pipedrive::BackfillJob.perform_later(hook.id, updated_since)
    puts "Enqueued Pipedrive backfill for account #{args[:account_id]} since #{updated_since}"
  end
end
