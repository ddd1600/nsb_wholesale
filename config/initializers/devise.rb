# frozen_string_literal: true

# NOTE: solidus_auth_devise's installer wrote a hardcoded Devise.secret_key here.
# It has been removed deliberately.
#
# That value derives every password-reset and account-claim token in the app, so
# committing it means anyone who can read the repository can mint a valid reset
# token for any account, including admins. With it gone, Devise falls back to
# Rails.application.secret_key_base, which comes from config/master.key locally
# and from the SECRET_KEY_BASE environment variable on Render -- neither of which
# is in git.
#
# Consequence to be aware of: SECRET_KEY_BASE must be set on Render (Rails 8
# refuses to boot in production without it), and rotating it invalidates any
# outstanding reset/claim links.

Devise.email_regexp = Spree::Config[:default_email_regexp]

Devise.setup do |config|
  config.parent_controller = 'StoreDeviseController'
  config.mailer = 'UserMailer'

  # Default is 6 hours, which is far too short for the B2BWave migration: the
  # announcement goes to ~360 customers at once and many will not read their
  # email the same day. The /claim page doubles as the resend mechanism, so an
  # expired link costs a customer one form submission.
  #
  # Worth shortening once the migration is done and this is only serving
  # ordinary "forgot my password" traffic.
  config.reset_password_within = 7.days

  # Password length is left at Devise's default (6..128) on purpose. Raising the
  # minimum to 8 was tried and reverted: Solidus's shipped :user factory uses the
  # 6-character password "secret", so a higher minimum breaks that factory and
  # the 24 spec files built on it. Hardening this later means overriding
  # Solidus's testing-support factory, which is a bigger change than it looks.
end
