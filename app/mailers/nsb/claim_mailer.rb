# frozen_string_literal: true

module Nsb
  # Separate from the reset-password email on purpose: a returning wholesale
  # customer setting up the new portal is a different message from "you forgot
  # your password", even though both carry a Devise reset token.
  #
  # Mirrors UserMailer (the class Devise is configured to use): inherit from
  # Spree::BaseMailer for from_address, and build URLs with the main app's
  # route helpers plus the store's host, since a mailer has no request to
  # infer one from.
  class ClaimMailer < Spree::BaseMailer
    def claim_instructions(user, token)
      @user = user
      @company_name = user.b2bwave_company_name
      @store = Spree::Store.default
      @expires_in_days = (Devise.reset_password_within / 1.day).to_i

      # Reuses the existing user_passwords#edit action to validate the token
      # and set the password.
      @claim_url = edit_spree_user_password_url(reset_password_token: token, host: mailer_host)
      @retry_url = claim_url(host: mailer_host)

      mail(
        to: user.email,
        from: from_address(@store),
        subject: "Set up your #{@store.name} wholesale account"
      )
    end

    private

    # Solidus builds email links from Spree::Store#url. If that is blank the URL
    # helper raises and the mail is never sent -- a silent, total email outage
    # from one empty admin field. Fall back to the configured mailer host so a
    # misconfigured store degrades to a wrong-looking link rather than no email.
    def mailer_host
      @store.url.presence ||
        ActionMailer::Base.default_url_options[:host].presence ||
        raise(ArgumentError, "Set Spree::Store#url or action_mailer.default_url_options[:host]")
    end
  end
end
