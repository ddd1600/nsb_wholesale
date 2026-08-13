# frozen_string_literal: true

module Spree
  # Square card payments.
  #
  # Inherits from Solidus's CreditCard payment method so the source is a
  # Spree::CreditCard -- which stores only the display fields (last four digits,
  # brand, expiry month/year) plus the single-use Square token. No PAN and no
  # CVV is ever accepted, logged or persisted; the browser tokenises with
  # Square's Web Payments SDK and posts only the token.
  #
  # Slots into the standard order state machine at the payment step; it does not
  # bypass it.
  class PaymentMethod::SquareCreditCard < PaymentMethod::CreditCard
    def gateway_class
      Nsb::Square::Gateway
    end

    # Renders app/views/checkouts/payment/_square.html.erb during checkout.
    def partial_name
      "square"
    end

    # Square tokens from the Web Payments SDK are single-use, so a stored source
    # cannot be charged again. Saying so keeps Solidus from offering a saved card
    # that would fail at capture. Repeat customers re-enter their card, which is
    # the honest trade until Square's Cards API is wired up.
    def reusable_sources(_order)
      []
    end

    def payment_profiles_supported?
      false
    end

    # Solidus asks whether a given source can be processed. A Square source is
    # usable exactly when the browser handed us a token.
    def supports?(source)
      source.respond_to?(:gateway_payment_profile_id) &&
        source.gateway_payment_profile_id.present?
    end

    # Surfaced in the admin so the operator can see, at a glance, which Square
    # account this method is talking to. Reads ENV; never stores the token.
    def configuration_summary
      config = Nsb::Square::Configuration.new
      if config.configured?
        "Square #{config.environment} (location #{config.location_id})"
      else
        "Square NOT configured - set SQUARE_ACCESS_TOKEN and SQUARE_LOCATION_ID"
      end
    end
  end
end
