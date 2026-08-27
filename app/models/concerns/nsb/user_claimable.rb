# frozen_string_literal: true

module Nsb
  # Lets a migrated B2BWave customer claim the account we created for them.
  #
  # Deliberately built on Devise's own reset-password token: set_reset_password_token
  # generates a random token, stores only its digest, and stamps
  # reset_password_sent_at for expiry. Writing bespoke token code here is exactly
  # the kind of thing that produces a quiet auth hole, so we reuse the tested path
  # and only change the wording of the email that carries it.
  #
  # Prepended onto Spree::User in config/initializers/solidus_decorators.rb.
  module UserClaimable
    extend ActiveSupport::Concern

    # True when the account came from the B2BWave migration and its password is
    # still the random one the importer assigned.
    def migrated_from_b2bwave?
      b2b_customer_id.present?
    end

    def b2bwave_company_name
      admin_metadata&.dig("b2bwave", "company_name")
    end

    # Called when this account is used for the first time -- the moment a
    # migrated customer finishes setting a password and can actually order.
    #
    # Idempotent on purpose. Every activation goes through Devise's
    # reset-password flow, and so does every ordinary "I forgot my password"
    # later on; without the timestamp guard the operator would be told the
    # customer activated again each time, which is wrong twice over.
    def record_activation!
      return false if nsb_activated_at.present?

      update_column(:nsb_activated_at, Time.current)
      Nsb::OperatorMailer.customer_activated(self).deliver_later
      true
    end

    # Mints a Devise reset token and returns the raw value, for a caller that
    # carries the link in its own message rather than the claim email -- an
    # approved application is being told something different from a migrated
    # customer, even though both land on the same set-password page.
    #
    # Public wrapper because Devise keeps set_reset_password_token protected, so
    # it can only be reached from inside the user.
    def issue_password_setup_token
      set_reset_password_token
    end

    # Mints a fresh token and emails the claim link. Returns the raw token so
    # specs can follow the link without parsing the email body.
    def send_claim_instructions
      raw_token = issue_password_setup_token
      Nsb::ClaimMailer.claim_instructions(self, raw_token).deliver_later
      raw_token
    end
  end
end
