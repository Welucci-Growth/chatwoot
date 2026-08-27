/* global axios */
import ApiClient from './ApiClient';

class GroupTeamAPI extends ApiClient {
  constructor() {
    super('group_team_members', { accountScoped: true });
  }

  add(phoneNumber, name) {
    return axios.post(this.url, { phone_number: phoneNumber, name });
  }

  remove(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  syncFromInstances() {
    return axios.post(`${this.url}/sync`);
  }
}

export default new GroupTeamAPI();
