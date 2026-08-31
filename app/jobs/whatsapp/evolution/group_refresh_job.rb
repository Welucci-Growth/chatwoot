# Walks every connected instance and refreshes the stored directory. Runs in the background
# because Evolution needs tens of seconds per instance and minutes for the whole fleet.
class Whatsapp::Evolution::GroupRefreshJob < ApplicationJob
  queue_as :low

  def perform(account_id = nil)
    accounts(account_id).each { |account| refresh(account) }
  end

  private

  def accounts(account_id)
    return Account.where(id: account_id) if account_id.present?

    Account.where(id: Channel::Whatsapp.where(provider: 'evolution').select(:account_id))
  end

  def refresh(account)
    service = Whatsapp::Evolution::GroupService.new
    return unless service.channel_for?(account)

    service.connected_instances.each do |instance|
      Whatsapp::Evolution::GroupSyncJob.perform_later(instance[:name])
    end
  rescue StandardError => e
    Rails.logger.error("[EVOLUTION_GROUPS] refresh failed for account #{account.id}: #{e.message}")
  end
end
