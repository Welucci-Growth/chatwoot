# Everything that shapes how LUCI answers, editable from the dashboard instead of by editing
# files over SSH. The bridge reads this on every message, so a save takes effect immediately.
# == Schema Information
#
# Table name: luci_settings
#
#  id             :bigint           not null, primary key
#  enabled        :boolean          default(FALSE), not null
#  knowledge      :text
#  model          :string           default("claude-haiku-4-5"), not null
#  required_label :string           default("luci"), not null
#  system_prompt  :text
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#
# Indexes
#
#  index_luci_settings_on_account_id  (account_id) UNIQUE
#
class LuciSetting < ApplicationRecord
  MODELS = %w[claude-haiku-4-5 claude-sonnet-5 claude-opus-5].freeze

  belongs_to :account

  validates :model, inclusion: { in: MODELS }
  validates :required_label, presence: true

  def self.for_account(account)
    find_or_create_by!(account: account)
  end
end
