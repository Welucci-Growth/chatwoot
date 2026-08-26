/* global axios */
import ApiClient from './ApiClient';

class EvolutionGroupsAPI extends ApiClient {
  constructor() {
    super('evolution_groups', { accountScoped: true });
  }

  getInstances() {
    return axios.get(this.url);
  }

  getGroupsForInstance(instance, refresh = false) {
    return axios.get(`${this.url}/by_instance`, {
      params: { instance, ...(refresh ? { refresh: 1 } : {}) },
    });
  }

  getDetails(instance, jid) {
    return axios.get(`${this.url}/details`, { params: { instance, jid } });
  }

  updateGroup(instance, jid, payload) {
    return axios.post(`${this.url}/update_group`, {
      instance,
      jid,
      ...payload,
    });
  }

  revokeInvite(instance, jid) {
    return axios.post(`${this.url}/revoke_invite`, { instance, jid });
  }

  updateAdmin(instance, jid, participant, actionType) {
    return axios.post(`${this.url}/update_admin`, {
      instance,
      jid,
      participant,
      action_type: actionType,
    });
  }
}

export default new EvolutionGroupsAPI();
