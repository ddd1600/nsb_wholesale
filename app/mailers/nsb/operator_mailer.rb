# frozen_string_literal: true

module Nsb
  # Emails to the people running the business, not to customers.
  #
  # Two events matter enough to interrupt someone: a new business has applied and
  # is waiting on a decision, and one of the 360 migrated accounts has come to
  # life. Both are things the operator would otherwise only discover by going to
  # look, and this portal is deliberately hands-off.
  class OperatorMailer < Spree::BaseMailer
    # Overridable without a deploy, because who wants these will change before
    # the code around them does.
    DEFAULT_RECIPIENTS = %w[david@newsouthbotanicals.com ddd1600@gmail.com].freeze

    def self.recipients
      ENV["OPERATOR_NOTIFICATION_EMAILS"].presence&.split(",")&.map(&:strip)&.reject(&:blank?) ||
        DEFAULT_RECIPIENTS
    end

    def application_received(application)
      @application = application
      @store = Spree::Store.default
      @review_url = admin_wholesale_application_url(application, host: mailer_host)

      mail(
        to: self.class.recipients,
        from: from_address(@store),
        subject: "Wholesale application: #{application.business_name}"
      )
    end

    def customer_activated(user)
      @user = user
      @company_name = user.b2bwave_company_name
      @store = Spree::Store.default

      mail(
        to: self.class.recipients,
        from: from_address(@store),
        subject: "Wholesale account activated: #{@company_name.presence || user.email}"
      )
    end

    private

    # Same fallback as ClaimMailer: an empty Spree::Store#url would otherwise
    # raise inside the URL helper and take out the email entirely.
    def mailer_host
      @store.url.presence ||
        ActionMailer::Base.default_url_options[:host].presence ||
        raise(ArgumentError, "Set Spree::Store#url or action_mailer.default_url_options[:host]")
    end
  end
end
