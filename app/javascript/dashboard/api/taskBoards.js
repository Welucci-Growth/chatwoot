/* global axios */
import ApiClient from './ApiClient';

class TaskBoardsAPI extends ApiClient {
  constructor() {
    super('task_boards', { accountScoped: true });
  }

  createColumn(boardId, data) {
    return axios.post(`${this.url}/${boardId}/task_columns`, data);
  }

  updateColumn(boardId, columnId, data) {
    return axios.patch(`${this.url}/${boardId}/task_columns/${columnId}`, data);
  }

  deleteColumn(boardId, columnId) {
    return axios.delete(`${this.url}/${boardId}/task_columns/${columnId}`);
  }
}

export default new TaskBoardsAPI();
