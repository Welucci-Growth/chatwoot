/* global axios */

import ApiClient from '../ApiClient';

class HubspotAPI extends ApiClient {
  constructor() {
    super('integrations/hubspot', { accountScoped: true });
  }

  getSegments() {
    return axios.get(`${this.url}/segments`);
  }

  updateSegments(segmentIds) {
    return axios.patch(`${this.url}/segments`, { segment_ids: segmentIds });
  }
}

export default new HubspotAPI();
