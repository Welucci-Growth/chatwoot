# == Schema Information
#
# Table name: task_boards
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  position   :integer          default(0), not null
#  visibility :integer          default("personal"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  owner_id   :bigint
#
# Indexes
#
#  index_task_boards_on_account_id  (account_id)
#  index_task_boards_on_owner_id    (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (owner_id => users.id)
#
class TaskBoard < ApplicationRecord
  belongs_to :account
  belongs_to :owner, class_name: 'User', optional: true

  has_many :task_columns, -> { order(position: :asc) }, dependent: :destroy, inverse_of: :task_board
  has_many :tasks, dependent: :destroy, inverse_of: :task_board

  enum visibility: { personal: 0, shared: 1 }

  validates :name, presence: true
  validates :account_id, presence: true

  # Boards a user can see: any shared board in the account, or their own personal board
  scope :accessible_by, ->(user) { where(visibility: :shared).or(where(owner_id: user.id)) }
end
