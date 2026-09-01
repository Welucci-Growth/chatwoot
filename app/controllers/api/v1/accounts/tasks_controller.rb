class Api::V1::Accounts::TasksController < Api::V1::Accounts::BaseController
  before_action :fetch_task, only: [:show, :update, :destroy, :move, :crm_panel, :crm_file]
  before_action :check_authorization

  def index
    @tasks = Current.account.tasks
                    .where(task_board_id: accessible_board_ids)
                    .includes(:assignee, :contact)
                    .order(position: :asc, created_at: :asc)
    @tasks = @tasks.where(task_board_id: params[:task_board_id]) if params[:task_board_id].present?
  end

  def show; end

  def create
    board = Current.account.task_boards.accessible_by(Current.user).find(params.dig(:task, :task_board_id))
    @task = board.tasks.create!(permitted_params.except(:task_board_id))
  end

  def update
    @task.update!(permitted_params)
  end

  def move
    @task.update!(task_column_id: params[:task_column_id], position: params[:position])
  end

  def destroy
    @task.destroy!
    head :ok
  end

  # Products, files, notes and activities of the mirrored CRM record, read on demand.
  def crm_panel
    render json: panel_service.new(@task).perform
  end

  # Cards can mirror either CRM; the HubSpot panel is assembled from stored data only.
  def panel_service
    @task.custom_attributes['hubspot'].present? ? Crm::Hubspot::DealPanelService : Crm::Pipedrive::DealPanelService
  end

  def crm_file
    file = Crm::Pipedrive::Api::Client.new(pipedrive_hook.settings['api_token']).download_file(params[:file_id])

    send_data file.body, type: file.headers['content-type'], disposition: 'inline'
  end

  private

  def fetch_task
    @task = Current.account.tasks.where(task_board_id: accessible_board_ids).find(params[:id])
  end

  def accessible_board_ids
    Current.account.task_boards.accessible_by(Current.user).select(:id)
  end

  def pipedrive_hook
    Current.account.hooks.find_by!(app_id: 'pipedrive')
  end

  def permitted_params
    params.require(:task).permit(
      :title, :description, :task_board_id, :task_column_id,
      :assignee_id, :contact_id, :conversation_id, :due_on, :position,
      label_list: []
    )
  end
end
