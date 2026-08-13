# == Schema Information
#
# Table name: task_columns
#
#  id            :bigint           not null, primary key
#  color         :string
#  name          :string           not null
#  position      :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  task_board_id :bigint           not null
#
# Indexes
#
#  index_task_columns_on_account_id     (account_id)
#  index_task_columns_on_task_board_id  (task_board_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (task_board_id => task_boards.id)
#
class TaskColumn < ApplicationRecord
  before_validation :ensure_account_id

  belongs_to :account
  belongs_to :task_board
  has_many :tasks, -> { order(position: :asc) }, dependent: :destroy, inverse_of: :task_column

  validates :name, presence: true
  validates :account_id, presence: true

  private

  def ensure_account_id
    self.account_id ||= task_board&.account_id
  end
end
