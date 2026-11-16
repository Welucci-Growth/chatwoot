require 'rails_helper'

describe Welucci::SsoProvisioningService do
  let(:account) { create(:account) }

  before { allow(Welucci::Hub).to receive(:account_id).and_return(account.id) }

  it 'lets an account an administrator set up ahead of time sign in, keeping how it was set up' do
    user = create(:user, email: 'financeiro@welucci.com', skip_confirmation: false)
    user.update_columns(confirmed_at: nil) # rubocop:disable Rails/SkipsModelValidations
    create(:account_user, account: account, user: user, role: :agent, access_profile: 'monitoring')

    signed_in = described_class.new(email: 'Financeiro@welucci.com', name: 'financeiro').perform

    expect(signed_in).to eq(user)
    expect(user.reload).to be_confirmed
    expect(account.account_users.find_by(user: user).access_profile).to eq('monitoring')
  end
end
