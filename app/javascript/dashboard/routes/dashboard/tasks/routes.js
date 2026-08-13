import { frontendURL } from '../../../helper/URLHelper';
import TasksView from './pages/TasksView.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/tasks'),
    name: 'tasks_dashboard_index',
    component: TasksView,
    meta: {
      permissions: ['administrator', 'agent'],
    },
  },
];
