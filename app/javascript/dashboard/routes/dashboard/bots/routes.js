import { frontendURL } from '../../../helper/URLHelper';
import BotsView from './pages/BotsView.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/bots'),
    name: 'bots_dashboard_index',
    component: BotsView,
    meta: {
      permissions: ['administrator'],
    },
  },
];
