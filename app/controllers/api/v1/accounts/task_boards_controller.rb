class Api::V1::Accounts::TaskBoardsController < Api::V1::Accounts::BaseController
  before_action :fetch_task_board, only: [:show, :update, :destroy]
  before_action :check_authorization

  DEFAULT_COLUMNS = ['Pendente', 'Em andamento', 'Concluído'].freeze

  def index
    @task_boards = Current.account.task_boards
                          .accessible_by(Current.user)
                          .includes(:owner)
                          .order(position: :asc, created_at: :asc)
  end

  def show; end

  def create
    ActiveRecord::Base.transaction do
      @task_board = Current.account.task_boards.create!(permitted_params.merge(owner: Current.user))
      DEFAULT_COLUMNS.each_with_index do |name, index|
        @task_board.task_columns.create!(name: name, position: index)
      end
    end
  end

  def update
    @task_board.update!(permitted_params)
  end

  def destroy
    @task_board.destroy!
    head :ok
  end

  private

  def fetch_task_board
    @task_board = Current.account.task_boards
                         .accessible_by(Current.user)
                         .includes(task_columns: { tasks: [:assignee, :contact] })
                         .find(params[:id])
  end

  def permitted_params
    params.require(:task_board).permit(:name, :visibility, :position)
  end
end
