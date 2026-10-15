# frozen_string_literal: true

module Nsb
  # Saves a customer's card with Square after a completed checkout, when they
  # ticked "Save this card". See Nsb::Square::CardsOnFile.
  #
  # Out of band on purpose, like the ShipStation push: the order is already
  # complete and paid, and nothing here may change that. If saving fails, the
  # customer simply enters their card next time.
  class SaveCardOnFileJob < ApplicationJob
    queue_as :default

    # Square made a decision (e.g. refused to store that card). Retrying will
    # not change it.
    #
    # Declared BEFORE retry_on: ServerError is a ResponseError subclass, and
    # Active Job checks the last-declared handler first.
    discard_on ::Square::Errors::ResponseError do |job, error|
      payment = job.arguments.first
      Rails.logger.error(
        "[square] could not save card for payment #{payment.try(:number)}: #{error.message.to_s.first(500)}"
      )
    end

    # Outcome unknown or Square briefly down. Retrying is safe: the card and
    # customer calls carry fixed idempotency keys.
    retry_on ::Square::Errors::TimeoutError, ::Square::Errors::ServerError,
      ::Square::Errors::ServiceUnavailableError,
      wait: :polynomially_longer, attempts: 5

    def perform(payment)
      return unless self.class.wanted?(payment)

      Nsb::Square::CardsOnFile.new.save_from_payment(payment)
      Rails.logger.info("[square] saved card on file for payment #{payment.number}")
    end

    # True when this payment's card should be saved and has not been yet.
    def self.wanted?(payment)
      card = payment.source
      payment.completed? &&
        payment.payment_method.is_a?(Spree::PaymentMethod::SquareCreditCard) &&
        card.is_a?(Spree::CreditCard) &&
        card.nsb_save_requested? &&
        card.gateway_customer_profile_id.blank? &&
        payment.order.user.present?
    end
  end
end
