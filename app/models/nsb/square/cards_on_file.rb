# frozen_string_literal: true

module Nsb
  module Square
    # Saved cards, held by Square ("card on file"). We keep only Square's ids and
    # the display fields (brand, last four, expiry) -- never card data.
    #
    # How a card gets saved:
    #   1. The customer ticks "Save this card" and checks out as normal. The
    #      single-use browser token is spent on that charge.
    #   2. AFTER Square has confirmed the charge, Nsb::SaveCardOnFileJob calls
    #      #save_from_payment, which asks Square to keep the card using the
    #      completed payment's id as the source.
    #
    # Saving never runs inside checkout, so a failure here cannot affect an
    # order or a charge. The worst case is the customer types their card again
    # next time.
    #
    # UNVERIFIED (2026-10-15): that Square's CreateCard accepts a completed
    # payment id as source_id is from Square's docs, not yet exercised against
    # the sandbox. See docs/SAVED_CARDS.md.
    class CardsOnFile
      def initialize(config: Nsb::Square::Configuration.new)
        @config = config
      end

      # Saves the card used for +payment+ with Square, then puts it in the
      # customer's Solidus wallet so checkout offers it next time.
      #
      # Square errors are raised to the caller (the job decides whether to
      # retry). Re-running is safe: the idempotency key is fixed per payment, so
      # Square returns the same card rather than storing a duplicate.
      def save_from_payment(payment)
        credit_card = payment.source
        user = payment.order.user
        raise ArgumentError, "payment #{payment.number} has no customer" unless user
        raise ArgumentError, "payment #{payment.number} has no Square payment id" if payment.response_code.blank?

        customer_id = ensure_customer(user)

        response = client.cards.create(
          idempotency_key: "card-#{payment.number}",
          source_id: payment.response_code,
          card: {
            customer_id: customer_id,
            cardholder_name: credit_card.name.presence,
            reference_id: "spree_credit_card_#{credit_card.id}"
          }.compact
        )
        card = response.card

        credit_card.update!(
          gateway_customer_profile_id: customer_id,
          gateway_payment_profile_id: card.id,
          last_digits: card.last_4.presence || credit_card.last_digits,
          month: card.exp_month || credit_card.month,
          year: card.exp_year || credit_card.year,
          user: user
        )
        user.wallet.add(credit_card)
        credit_card
      end

      # Tells Square to stop keeping the card. Square has no delete; a disabled
      # card can never be charged again.
      #
      # Returns true when Square confirms, or when Square no longer knows the
      # card (already disabled or removed) -- either way it cannot be charged.
      def disable(credit_card)
        card_id = credit_card.gateway_payment_profile_id
        return true if card_id.blank?

        response = client.cards.disable(card_id: card_id)
        response.card&.enabled == false
      rescue ::Square::Errors::NotFoundError
        true
      end

      private

      attr_reader :config

      # One Square customer per portal user, created on first save.
      def ensure_customer(user)
        return user.square_customer_id if user.square_customer_id.present?

        user.with_lock do
          return user.square_customer_id if user.square_customer_id.present?

          response = client.customers.create(
            idempotency_key: "customer-spree-user-#{user.id}",
            email_address: user.email,
            reference_id: "spree_user_#{user.id}",
            note: "Wholesale portal customer"
          )
          user.update_column(:square_customer_id, response.customer.id)
          response.customer.id
        end
      end

      def client
        @client ||= config.client
      end
    end
  end
end
