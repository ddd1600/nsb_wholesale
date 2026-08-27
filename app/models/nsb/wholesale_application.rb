# frozen_string_literal: true

module Nsb
  # A business asking to become a wholesale customer.
  #
  # The storefront is closed: pricing and ordering need an account, and accounts
  # are not self-serve. Existing B2BWave customers claim the account already
  # created for them (Nsb::UserClaimable); everyone else applies here and waits
  # for the operator to approve.
  #
  # Approval is what creates the Spree::User. Until then this row is all that
  # exists, so an unvetted applicant never appears in the customer list.
  class WholesaleApplication < ApplicationRecord
    self.table_name = "nsb_wholesale_applications"

    STATUSES = %w[pending approved declined].freeze

    belongs_to :user, class_name: "Spree::User", optional: true

    # Every field on the form is required. This is a licence-gated wholesale
    # account, not a newsletter signup -- a half-filled application cannot be
    # judged, and chasing the rest by email is worse for both sides than the
    # applicant filling it in now.
    validates :business_name, :contact_name, :email, :phone, :address,
      :retail_license_state, :retail_license_number,
      :sells, :interested_in, :heard_about_us,
      presence: true

    validates :status, inclusion: { in: STATUSES }

    # Deliberately loose. Address validation beyond "looks like an email" rejects
    # real addresses, and the approval email is the real test of whether it works.
    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

    # One pending application per address. Without this a refresh or an impatient
    # second submission puts two rows in front of the operator to compare.
    validate :no_pending_application_for_email, on: :create

    normalizes :email, with: ->(email) { email.to_s.strip.downcase }
    normalizes :retail_license_state, with: ->(state) { state.to_s.strip.upcase }

    scope :pending, -> { where(status: "pending") }
    scope :reviewed, -> { where.not(status: "pending") }
    scope :newest_first, -> { order(created_at: :desc) }

    def pending? = status == "pending"
    def approved? = status == "approved"
    def declined? = status == "declined"

    # The account this applicant would claim, if one already exists. Checked
    # before the form is accepted: 360 migrated customers make it likely that
    # someone applies for an account they already have.
    def existing_account
      Spree.user_class.find_by("lower(email) = ?", email)
    end

    # Creates the account and emails the applicant a link to set a password.
    #
    # Approval is the only thing that creates a Spree::User here, so until an
    # operator has looked at the application no unvetted row exists in the
    # customer list. The password set here is a long random secret the applicant
    # never learns, exactly as Nsb::CustomerImporter does for migrated accounts:
    # the reset token in the email is what actually lets them in.
    def approve!
      raise ArgumentError, "application #{id} is already #{status}" unless pending?

      token = nil

      transaction do
        account = existing_account || Spree.user_class.create!(
          email: email,
          password: SecureRandom.base58(48)
        )
        token = account.issue_password_setup_token
        update!(status: "approved", reviewed_at: Time.current, user: account)
      end

      # Outside the transaction: a mail failure must not roll back an approval
      # the operator has already made. Delivery is a job, so it survives a
      # restart and can be retried on its own.
      Nsb::ApprovalMailer.approved(self, token).deliver_later
      self
    end

    # Silent by design, at the operator's request: it marks the row reviewed so
    # it leaves the pending list, and sends the applicant nothing.
    def decline!
      raise ArgumentError, "application #{id} is already #{status}" unless pending?

      update!(status: "declined", reviewed_at: Time.current)
      self
    end

    private

    def no_pending_application_for_email
      return if email.blank?
      return unless self.class.pending.where("lower(email) = ?", email).exists?

      errors.add(:email, :taken)
    end
  end
end
