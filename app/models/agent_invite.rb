# == Schema Information
#
# Table name: agent_invites
#
#  id         :bigint           not null, primary key
#  enabled    :boolean          default(TRUE), not null
#  role       :integer          default("agent"), not null
#  token      :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  inviter_id :bigint
#  team_id    :bigint
#
# Indexes
#
#  index_agent_invites_on_account_id  (account_id)
#  index_agent_invites_on_inviter_id  (inviter_id)
#  index_agent_invites_on_team_id     (team_id)
#  index_agent_invites_on_token       (token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (inviter_id => users.id)
#  fk_rails_...  (team_id => teams.id)
#
class AgentInvite < ApplicationRecord
  belongs_to :account
  belongs_to :inviter, class_name: 'User', optional: true
  belongs_to :team, optional: true

  enum role: { agent: 0, administrator: 1 }

  before_validation :ensure_token, on: :create
  validates :token, presence: true, uniqueness: true
  validates :account_id, presence: true

  scope :active, -> { where(enabled: true) }

  def invite_url
    "#{ENV.fetch('FRONTEND_URL', '')}/app/auth/welucci-invite/#{token}"
  end

  private

  def ensure_token
    self.token ||= SecureRandom.urlsafe_base64(24)
  end
end
