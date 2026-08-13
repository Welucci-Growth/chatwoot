/* global axios */
import ApiClient from './ApiClient';

class TasksAPI extends ApiClient {
  constructor() {
    super('tasks', { accountScoped: true });
  }

  move(id, { taskColumnId, position }) {
    return axios.patch(`${this.url}/${id}/move`, {
      task_column_id: taskColumnId,
      position,
    });
  }
}

export default new TasksAPI();
