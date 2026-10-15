# frozen_string_literal: true

module Nsb
  # Prepended onto Spree::CreditCard: decides which Square cards count as saved.
  #
  # Solidus treats a card as reusable when it has ANY gateway profile id. Square
  # cards always do -- the browser's single-use token sits in
  # gateway_payment_profile_id -- so stock Solidus put every Square card in the
  # customer's wallet and offered it at checkout, where charging the spent token
  # would fail.
  #
  # A Square card is reusable only once Square has stored it, which is when
  # Nsb::Square::CardsOnFile fills in the Square customer id.
  module SquareSavedCard
    def reusable?
      return super unless payment_method.is_a?(Spree::PaymentMethod::SquareCreditCard)

      gateway_customer_profile_id.present?
    end
  end
end
