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

    # What Google said about an address, recorded so the operator sees it when
    # deciding. "unverified" is not a reason to decline on its own -- plenty of
    # real addresses cannot be confirmed -- but it is worth a second look.
    VERDICTS = %w[confirmed unverified unchecked].freeze

    def address_unverified? = address_verdict == "unverified"
    def shipping_address_unverified? = shipping_address_verdict == "unverified"

    belongs_to :user, class_name: "Spree::User", optional: true

    # What the operator actually decides on: who you are, how to reach you, and
    # the license. The three "tell us about your business" questions are useful
    # colour but are not worth losing an applicant over, so they stay optional.
    REQUIRED_FIELDS = %i[
      business_name contact_name email phone address
      retail_license_state retail_license_number
    ].freeze

    validates(*REQUIRED_FIELDS, presence: true)

    # Two letters, and a state we actually recognise. The form offers a dropdown,
    # so anything else arrived by hand-crafted request rather than by typo.
    validates :retail_license_state,
      inclusion: { in: ->(_) { Nsb::UsStates.codes } },
      allow_blank: true

    # Ten digits, once punctuation is stripped, optionally with a leading US
    # country code. Deliberately not stricter: area-code and exchange rules
    # change, and rejecting a real number to enforce a lookup table nobody
    # maintains is the worse failure.
    validates :phone,
      format: { with: /\A\(\d{3}\) \d{3}-\d{4}\z/, message: :invalid_us_phone },
      allow_blank: true

    validates :status, inclusion: { in: STATUSES }

    # Deliberately loose. Address validation beyond "looks like an email" rejects
    # real addresses, and the approval email is the real test of whether it works.
    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

    # One pending application per address. Without this a refresh or an impatient
    # second submission puts two rows in front of the operator to compare.
    validate :no_pending_application_for_email, on: :create

    normalizes :email, with: ->(email) { email.to_s.strip.downcase }
    normalizes :retail_license_state, with: ->(state) { state.to_s.strip.upcase }

    # Stored one way, however it was typed, so the operator reading a list of
    # applications is not also parsing three phone formats. The browser formats
    # as you type; this is what makes it true for anyone who bypasses that.
    normalizes :phone, with: ->(phone) { Nsb::PhoneNumber.format(phone) }

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
