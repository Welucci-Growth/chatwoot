import ApiClient from './ApiClient';

class AgentInvitesAPI extends ApiClient {
  constructor() {
    super('agent_invites', { accountScoped: true });
  }
}

export default new AgentInvitesAPI();
