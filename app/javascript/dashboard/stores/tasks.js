/* eslint-disable no-param-reassign */
import { defineStore } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import TaskBoardsAPI from 'dashboard/api/taskBoards';
import TasksAPI from 'dashboard/api/tasks';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const camelize = data =>
  camelcaseKeys(data || {}, { deep: true, stopPaths: ['custom_attributes'] });

export const useTasksStore = defineStore('tasks', {
  state: () => ({
    boards: [],
    activeBoard: null,
    uiFlags: {
      fetchingBoards: false,
      fetchingBoard: false,
      mutating: false,
    },
  }),

  getters: {
    boardList: state => state.boards,
    columns: state => state.activeBoard?.columns || [],
  },

  actions: {
    findColumn(columnId) {
      return this.activeBoard?.columns?.find(column => column.id === columnId);
    },

    async fetchBoards() {
      this.uiFlags.fetchingBoards = true;
      try {
        const { data } = await TaskBoardsAPI.get();
        this.boards = camelize(data);
        return this.boards;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.uiFlags.fetchingBoards = false;
      }
    },

    // Fetch a board's detail (with columns + tasks) without mutating activeBoard.
    // Used by dialogs (e.g. creating a task from a conversation) that need a
    // board's columns without disturbing the Kanban view.
    async getBoardDetail(id) {
      const { data } = await TaskBoardsAPI.show(id);
      return camelize(data);
    },

    async fetchBoard(id) {
      this.uiFlags.fetchingBoard = true;
      try {
        const { data } = await TaskBoardsAPI.show(id);
        this.activeBoard = camelize(data);
        return this.activeBoard;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.uiFlags.fetchingBoard = false;
      }
    },

    async createBoard({ name, visibility = 'personal' }) {
      const { data } = await TaskBoardsAPI.create({
        task_board: { name, visibility },
      });
      const board = camelize(data);
      this.boards.push(board);
      return board;
    },

    async updateBoard(id, attrs) {
      const { data } = await TaskBoardsAPI.update(id, { task_board: attrs });
      const board = camelize(data);
      const index = this.boards.findIndex(item => item.id === id);
      if (index !== -1)
        this.boards[index] = { ...this.boards[index], ...board };
      if (this.activeBoard?.id === id) {
        this.activeBoard = { ...this.activeBoard, ...board };
      }
      return board;
    },

    async deleteBoard(id) {
      await TaskBoardsAPI.delete(id);
      this.boards = this.boards.filter(board => board.id !== id);
      if (this.activeBoard?.id === id) this.activeBoard = null;
    },

    async createColumn(boardId, { name, color }) {
      const { data } = await TaskBoardsAPI.createColumn(boardId, {
        task_column: { name, color },
      });
      const column = camelize(data);
      if (this.activeBoard?.id === boardId) {
        this.activeBoard.columns.push({ ...column, tasks: [] });
      }
      return column;
    },

    async updateColumn(boardId, columnId, attrs) {
      const { data } = await TaskBoardsAPI.updateColumn(boardId, columnId, {
        task_column: attrs,
      });
      const column = camelize(data);
      const existing = this.findColumn(columnId);
      if (existing) Object.assign(existing, column);
      return column;
    },

    async deleteColumn(boardId, columnId) {
      await TaskBoardsAPI.deleteColumn(boardId, columnId);
      if (this.activeBoard?.id === boardId) {
        this.activeBoard.columns = this.activeBoard.columns.filter(
          column => column.id !== columnId
        );
      }
    },

    async createTask(payload) {
      const { data } = await TasksAPI.create({ task: payload });
      const task = camelize(data);
      const column = this.findColumn(task.taskColumnId);
      if (column) column.tasks.push(task);
      return task;
    },

    async updateTask(id, payload) {
      const { data } = await TasksAPI.update(id, { task: payload });
      const task = camelize(data);
      this.replaceTaskLocally(task);
      return task;
    },

    async deleteTask(id) {
      await TasksAPI.delete(id);
      this.activeBoard?.columns?.forEach(column => {
        column.tasks = column.tasks.filter(task => task.id !== id);
      });
    },

    // The list order is mutated locally by the draggable component; persist here.
    async persistMove({ id, toColumnId, position }) {
      const { data } = await TasksAPI.move(id, {
        taskColumnId: toColumnId,
        position,
      });
      return camelize(data);
    },

    replaceTaskLocally(task) {
      this.activeBoard?.columns?.forEach(column => {
        const index = column.tasks.findIndex(item => item.id === task.id);
        if (index === -1) return;
        if (column.id === task.taskColumnId) column.tasks[index] = task;
        else column.tasks.splice(index, 1);
      });
      const target = this.findColumn(task.taskColumnId);
      if (target && !target.tasks.some(item => item.id === task.id)) {
        target.tasks.push(task);
      }
    },
  },
});
