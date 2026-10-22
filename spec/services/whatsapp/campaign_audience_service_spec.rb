require 'rails_helper'

describe Whatsapp::CampaignAudienceService do
  let(:account) { create(:account) }
  let(:label) { create(:label, account: account, title: 'hs-clientes') }
  let!(:reachable) { create(:contact, account: account, phone_number: '+5511988887777') }
  let!(:opted_out) { create(:contact, account: account, phone_number: '+5511977776666') }
  let!(:without_phone) { create(:contact, account: account, email: 'sem@telefone.com', phone_number: nil) }
  let!(:blocked) { create(:contact, account: account, phone_number: '+5511966665555', blocked: true) }
  let(:service) { described_class.new(account: account, label_ids: [label.id]) }

  before do
    create(:contact, account: account, phone_number: '+5511955554444')
    [reachable, opted_out, without_phone, blocked].each { |contact| contact.update!(label_list: [label.title]) }
    opted_out.add_labels([described_class::OPT_OUT_LABEL])
  end

  it 'reaches only labelled contacts with a phone that are neither opted out nor blocked' do
    expect(service.recipients).to contain_exactly(reachable)
  end

  it 'reports who is left out and why' do
    expect(service.summary).to include(labelled: 4, without_phone: 1, opted_out: 1, blocked: 1, recipients: 1, test_mode: false)
  end

  it 'reaches nobody without labels' do
    expect(described_class.new(account: account, label_ids: []).recipients).to be_empty
  end

  context 'when test numbers are configured' do
    it 'reaches only the test numbers, with or without the ninth digit' do
      tester = create(:contact, account: account, phone_number: '+551188881111', label_list: [label.title])

      with_modified_env CAMPAIGN_TEST_PHONE_NUMBERS: '11 98888-1111' do
        expect(service.recipients).to contain_exactly(tester)
        expect(service.summary[:test_mode]).to be(true)
      end
    end

    it 'reaches nobody when none of the test numbers is valid' do
      with_modified_env CAMPAIGN_TEST_PHONE_NUMBERS: 'xyz' do
        expect(service.recipients).to be_empty
      end
    end
  end
end
