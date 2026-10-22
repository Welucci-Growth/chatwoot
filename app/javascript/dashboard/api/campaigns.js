/* global axios */
import ApiClient from './ApiClient';

class CampaignsAPI extends ApiClient {
  constructor() {
    super('campaigns', { accountScoped: true });
  }

  audiencePreview(labelIds) {
    return axios.get(`${this.url}/audience_preview`, {
      params: { label_ids: labelIds },
    });
  }
}

export default new CampaignsAPI();
