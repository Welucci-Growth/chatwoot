class Api::V1::Accounts::TaskBoards::TaskColumnsController < Api::V1::Accounts::BaseController
  before_action :fetch_task_board
  before_action :fetch_task_column, only: [:update, :destroy]
  before_action :check_authorization

  def create
    @task_column = @task_board.task_columns.create!(permitted_params)
  end

  def update
    @task_column.update!(permitted_params)
  end

  def destroy
    @task_column.destroy!
    head :ok
  end

  private

  def fetch_task_board
    @task_board = Current.account.task_boards.accessible_by(Current.user).find(params[:task_board_id])
  end

  def fetch_task_column
    @task_column = @task_board.task_columns.find(params[:id])
  end

  def permitted_params
    params.require(:task_column).permit(:name, :color, :position)
  end
end
