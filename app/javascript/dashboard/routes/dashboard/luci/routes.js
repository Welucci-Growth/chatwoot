import { frontendURL } from '../../../helper/URLHelper';
import LuciView from './pages/LuciView.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/luci'),
    name: 'luci_dashboard_index',
    component: LuciView,
    meta: {
      permissions: ['administrator'],
    },
  },
];
