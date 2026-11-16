namespace :evolution do
  # Connects another number from the Evolution server that already backs the mirror, as a
  # read-only inbox. It starts paused and HistoryImportJob turns it on once the recent history
  # is in, so the thread reads in order.
  desc 'Connect an Evolution instance as a mirror inbox: rake "evolution:connect_mirror[contas_a_pagar,Contas a Pagar,30]"'
  task :connect_mirror, %i[instance name days] => :environment do |_task, args|
    server = Channel::Whatsapp.find_by!(provider: 'evolution')
    remote = Whatsapp::Evolution::GroupService.new.connected_instances.find { |i| i[:name] == args[:instance] }
    raise "Evolution has no connected instance named #{args[:instance]}" if remote.blank?

    channel = Channel::Whatsapp.create!(
      account: server.account, provider: 'evolution', phone_number: "+#{remote[:number]}",
      provider_config: server.provider_config.slice('base_url', 'api_key').merge('instance' => args[:instance], 'mirror_paused' => true)
    )
    # Nobody answers from a mirror, so there is nothing to hand out.
    inbox = server.account.inboxes.create!(name: args[:name], channel: channel, enable_auto_assignment: false)
    days = Integer(args[:days] || 30)
    Whatsapp::Evolution::HistoryImportJob.perform_later(inbox.id, days)
    puts "Inbox #{inbox.id} '#{inbox.name}': espelho pausado, importando #{days} dias de historico"
  end
end
