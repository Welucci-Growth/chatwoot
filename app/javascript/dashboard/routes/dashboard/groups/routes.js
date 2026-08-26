import { frontendURL } from '../../../helper/URLHelper';
import GroupsView from './pages/GroupsView.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/groups'),
    name: 'groups_dashboard_index',
    component: GroupsView,
    meta: {
      permissions: ['administrator'],
    },
  },
];
