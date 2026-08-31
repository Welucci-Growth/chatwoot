/* global axios */
import ApiClient from './ApiClient';

class LuciAPI extends ApiClient {
  constructor() {
    super('luci_settings', { accountScoped: true });
  }

  getSettings() {
    return axios.get(this.url);
  }

  updateSettings(payload) {
    return axios.patch(this.url, payload);
  }
}

export default new LuciAPI();
