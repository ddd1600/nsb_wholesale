# frozen_string_literal: true

module Nsb
  # Tells an applicant their wholesale account has been approved, and carries the
  # link that lets them set a password.
  #
  # Separate from ClaimMailer because the two audiences are not the same: a
  # migrated customer is being told their existing account has moved, while this
  # reader has been waiting on a decision and is being told the answer. Both
  # carry a Devise reset token and land on the same set-password page.
  class ApprovalMailer < Spree::BaseMailer
    def approved(application, token)
      @application = application
      @store = Spree::Store.default
      @expires_in_days = (Devise.reset_password_within / 1.day).to_i
      @set_password_url = edit_spree_user_password_url(reset_password_token: token, host: mailer_host)
      @recover_url = recover_password_url(host: mailer_host)

      mail(
        to: application.email,
        from: from_address(@store),
        subject: "Your #{@store.name} wholesale account is approved"
      )
    end

    private

    def mailer_host
      @store.url.presence ||
        ActionMailer::Base.default_url_options[:host].presence ||
        raise(ArgumentError, "Set Spree::Store#url or action_mailer.default_url_options[:host]")
    end
  end
end
