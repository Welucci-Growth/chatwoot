/* global axios */
import ApiClient from './ApiClient';

class TasksAPI extends ApiClient {
  constructor() {
    super('tasks', { accountScoped: true });
  }

  crmPanel(id) {
    return axios.get(`${this.url}/${id}/crm_panel`);
  }

  crmFile(id, fileId) {
    return axios.get(`${this.url}/${id}/crm_files/${fileId}`, {
      responseType: 'blob',
    });
  }

  move(id, { taskColumnId, position }) {
    return axios.patch(`${this.url}/${id}/move`, {
      task_column_id: taskColumnId,
      position,
    });
  }
}

export default new TasksAPI();
