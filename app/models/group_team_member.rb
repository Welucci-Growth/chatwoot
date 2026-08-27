# Who counts as staff inside a WhatsApp group. Everyone else who speaks is treated as a
# client, which is what lets a group be flagged as waiting for a reply.
# == Schema Information
#
# Table name: group_team_members
#
#  id           :bigint           not null, primary key
#  name         :string
#  phone_number :string           not null
#  source       :string           default("manual"), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#
# Indexes
#
#  index_group_team_members_on_account_id                   (account_id)
#  index_group_team_members_on_account_id_and_phone_number  (account_id,phone_number) UNIQUE
#
class GroupTeamMember < ApplicationRecord
  belongs_to :account

  validates :phone_number, presence: true, uniqueness: { scope: :account_id }

  scope :phone_numbers_for, ->(account) { where(account: account).pluck(:phone_number) }

  before_validation :normalize_phone_number

  private

  # Numbers arrive from Evolution as JIDs and from agents as free text; store digits only so
  # both sides compare cleanly.
  def normalize_phone_number
    self.phone_number = phone_number.to_s.split('@').first.gsub(/\D/, '')
  end
end
