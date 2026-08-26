# Turns an identity the Hub has already vouched for into a Chatwoot user that can hold a
# session.
#
# Who may enter is decided upstream: the Hub only mints a token for someone holding the
# `chatwoot` permission. So a first arrival is provisioned here rather than invited — the
# same lazy provisioning every other Welucci app does.
#
# Two things this deliberately never does:
#
#   * grant `administrator` — everyone lands as `agent`, and promotion stays a deliberate
#     act inside Chatwoot, so holding admin in the Hub does not silently hand someone admin
#     over the inboxes;
#   * touch an existing membership — a person promoted by hand inside Chatwoot keeps that
#     role, and their name stays whatever they set it to here.
#
# The join key is the email address, which is also the Hub's own identifier for a person. An
# address that already exists in Chatwoot is adopted, never duplicated.
class Welucci::SsoProvisioningService
  pattr_initialize [:email!, :name]

  def perform
    normalized_email = email.to_s.strip.downcase
    # A verified identity from the Hub always carries an address; no address means the
    # contract between the two apps is broken, and that should be loud.
    raise ArgumentError, 'Welucci Hub returned an identity with no email' if normalized_email.blank?

    account = Account.find(Welucci::Hub.account_id)

    ActiveRecord::Base.transaction do
      user = find_or_create_user(normalized_email)
      ensure_membership(account, user)
      user
    end
  end

  private

  def find_or_create_user(normalized_email)
    existing = User.from_email(normalized_email)
    return existing if existing

    user = User.new(
      name: display_name(normalized_email),
      email: normalized_email,
      # Login for these addresses goes through the Hub, so this value is never used to sign
      # in. It exists because Devise requires one, and it is random so that it stays
      # unusable even if enforcement is later turned off. The `aA1!` tail satisfies the
      # installation's password content policy — same trick as the omniauth callback.
      password: "#{SecureRandom.hex(16)}aA1!"
    )
    # The Hub has already verified the address, so a confirmation email here would be a
    # dead end.
    user.skip_confirmation!
    user.save!
    user
  end

  def ensure_membership(account, user)
    return if account.account_users.exists?(user_id: user.id)

    AccountUser.create!(account: account, user: user, role: :agent)
  end

  # The Hub sends a username (`marcel.rodriguez`), not a display name. Chatwoot shows this
  # on every conversation, so turn it into something readable; the person can change it in
  # their profile afterwards and we never overwrite it again.
  def display_name(normalized_email)
    source = name.presence || normalized_email.split('@').first
    source.to_s.split(/[._-]+/).compact_blank.map(&:capitalize).join(' ').presence || normalized_email
  end
end
