# frozen_string_literal: true

module Nsb
  # Enqueues Nsb::SaveCardOnFileJob when an order is finalized, for each Square
  # payment whose card the customer asked us to save.
  #
  # Only enqueueing happens here, never the Square call: :order_finalized is
  # published inside the order's transaction, and an error here must not roll
  # back an order Square has already charged. Same reasoning as
  # Nsb::ShipstationSubscriber.
  class SaveCardSubscriber
    include Omnes::Subscriber

    handle :order_finalized,
      with: :save_cards,
      id: :nsb_save_card_on_file

    def save_cards(event)
      order = event[:order]
      order.payments.each do |payment|
        Nsb::SaveCardOnFileJob.perform_later(payment) if Nsb::SaveCardOnFileJob.wanted?(payment)
      end
    rescue => error
      Rails.logger.error("[square] could not enqueue card save for #{order&.number}: #{error.message}")
    end
  end
end
