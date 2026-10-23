require 'rails_helper'

RSpec.describe Contacts::BulkActionService do
  subject(:service) { described_class.new(account: account, user: user, params: params) }

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe '#perform' do
    context 'when delete action is requested via action_name' do
      let(:params) { { ids: [1, 2], action_name: 'delete' } }

      it 'delegates to the bulk delete service' do
        bulk_delete_service = instance_double(Contacts::BulkDeleteService, perform: true)

        expect(Contacts::BulkDeleteService).to receive(:new)
          .with(account: account, contact_ids: [1, 2])
          .and_return(bulk_delete_service)

        service.perform
      end
    end

    context 'when labels are provided' do
      let(:params) { { ids: [10, 20], labels: { add: %w[vip support] }, extra: 'ignored' } }

      it 'delegates to the bulk assign labels service with permitted params' do
        bulk_assign_service = instance_double(Contacts::BulkAssignLabelsService, perform: true)

        expect(Contacts::BulkAssignLabelsService).to receive(:new)
          .with(account: account, contact_ids: [10, 20], labels: %w[vip support])
          .and_return(bulk_assign_service)

        service.perform
      end
    end

    context 'when a filter is sent instead of ids' do
      let(:filter) do
        { payload: [{ attribute_key: 'phone_number', filter_operator: 'equal_to', values: ['+5511988887777'], query_operator: nil }] }
      end
      let!(:matching) { create(:contact, account: account, phone_number: '+5511988887777') }

      before { create(:contact, account: account, phone_number: '+5511977776666') }

      it 'labels every contact the filter matches' do
        described_class.new(account: account, user: user, params: { filter: filter, labels: { add: ['vip'] } }).perform

        expect(account.contacts.tagged_with('vip')).to contain_exactly(matching)
      end

      it 'leaves out the contacts unticked after selecting every match' do
        params = { filter: filter, exclude_ids: [matching.id], labels: { add: ['vip'] } }

        described_class.new(account: account, user: user, params: params).perform

        expect(account.contacts.tagged_with('vip')).to be_empty
      end

      it 'refuses to delete by filter' do
        result = described_class.new(account: account, user: user, params: { filter: filter, action_name: 'delete' }).perform

        expect(result).to eq(success: false, error: 'filter_not_allowed_for_delete')
        expect(account.contacts.count).to eq(2)
      end
    end

    context 'when labels are removed' do
      let(:params) { { ids: [10, 20], labels: { remove: %w[vip] }, extra: 'ignored' } }

      it 'delegates to the bulk remove labels service with permitted params' do
        bulk_remove_service = instance_double(Contacts::BulkRemoveLabelsService, perform: true)

        expect(Contacts::BulkRemoveLabelsService).to receive(:new)
          .with(account: account, contact_ids: [10, 20], labels: %w[vip])
          .and_return(bulk_remove_service)

        service.perform
      end
    end
  end
end
