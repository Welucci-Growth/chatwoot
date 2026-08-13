# == Schema Information
#
# Table name: tasks
#
#  id                :bigint           not null, primary key
#  custom_attributes :jsonb
#  description       :text
#  due_on            :datetime
#  position          :integer          default(0), not null
#  title             :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  assignee_id       :bigint
#  contact_id        :bigint
#  conversation_id   :bigint
#  task_board_id     :bigint           not null
#  task_column_id    :bigint           not null
#
# Indexes
#
#  index_tasks_on_account_id       (account_id)
#  index_tasks_on_assignee_id      (assignee_id)
#  index_tasks_on_contact_id       (contact_id)
#  index_tasks_on_conversation_id  (conversation_id)
#  index_tasks_on_task_board_id    (task_board_id)
#  index_tasks_on_task_column_id   (task_column_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (assignee_id => users.id)
#  fk_rails_...  (task_board_id => task_boards.id)
#  fk_rails_...  (task_column_id => task_columns.id)
#
class Task < ApplicationRecord
  include Labelable

  before_validation :ensure_account_id

  belongs_to :account
  belongs_to :task_board
  belongs_to :task_column
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :contact, optional: true
  belongs_to :conversation, optional: true

  validates :title, presence: true
  validates :account_id, presence: true

  scope :latest, -> { order(created_at: :desc) }

  def overdue?
    due_on.present? && due_on < Time.current
  end

  private

  def ensure_account_id
    self.account_id ||= task_board&.account_id
  end
end
