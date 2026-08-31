# A WhatsApp group as Evolution knows it. Stored rather than cached because listing every
# group takes minutes, and nobody should wait for that when opening the dashboard.
# == Schema Information
#
# Table name: whatsapp_groups
#
#  id            :bigint           not null, primary key
#  announce_only :boolean          default(FALSE), not null
#  description   :text
#  instance      :string           not null
#  jid           :string           not null
#  locked        :boolean          default(FALSE), not null
#  owner         :string
#  size          :integer
#  subject       :string
#  synced_at     :datetime
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#
# Indexes
#
#  index_whatsapp_groups_on_account_id               (account_id)
#  index_whatsapp_groups_on_account_id_and_instance  (account_id,instance)
#  index_whatsapp_groups_on_account_id_and_jid       (account_id,jid) UNIQUE
#
class WhatsappGroup < ApplicationRecord
  belongs_to :account

  validates :jid, presence: true, uniqueness: { scope: :account_id }
  validates :instance, presence: true

  scope :for_instance, ->(instance) { where(instance: instance) }
end
