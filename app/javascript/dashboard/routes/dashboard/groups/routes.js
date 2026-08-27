import { frontendURL } from '../../../helper/URLHelper';
import GroupsView from './pages/GroupsView.vue';
import GroupTeamView from './pages/GroupTeamView.vue';

// One route per sidebar entry so the active item highlights, all rendering the same view
// with a different filter.
const view = (path, name, filter) => ({
  path: frontendURL(path),
  name,
  component: GroupsView,
  props: () => ({ filter }),
  meta: {
    permissions: ['administrator'],
  },
});

export const routes = [
  view('accounts/:accountId/groups', 'groups_dashboard_index', 'all'),
  view(
    'accounts/:accountId/groups/active',
    'groups_dashboard_active',
    'active'
  ),
  view('accounts/:accountId/groups/idle', 'groups_dashboard_idle', 'idle'),
  {
    path: frontendURL('accounts/:accountId/groups/team'),
    name: 'groups_dashboard_team',
    component: GroupTeamView,
    meta: {
      permissions: ['administrator'],
    },
  },
];
