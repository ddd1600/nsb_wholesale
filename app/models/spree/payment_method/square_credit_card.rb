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

    # Cards the customer has saved with Square (see Nsb::Square::CardsOnFile).
    # Offered at checkout and on the admin's "New payment" form.
    #
    # Always the customer's wallet, even for a completed order: stock Solidus
    # would offer only the cards already used on that order, but the admin
    # adding a payment to a finished order should see every saved card.
    #
    # Single-use browser tokens are excluded by Nsb::SquareSavedCard#reusable?.
    def reusable_sources(order)
      return [] unless order.user

      order.user.wallet.wallet_payment_sources
        .map(&:payment_source)
        .select { |source| source.is_a?(Spree::CreditCard) && source.payment_method_id == id && source.reusable? }
    end

    # Stays false. Turning it on would make Solidus call #create_profile before
    # the charge and change the gateway's void signature. Cards are saved after
    # a confirmed charge instead, by Nsb::SaveCardOnFileJob.
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
