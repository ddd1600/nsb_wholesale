# frozen_string_literal: true

module Nsb
  # Enqueues the ShipStation push when an order is finalized.
  #
  # Solidus publishes :order_finalized from inside the order's state-machine
  # transaction. Only enqueueing happens here -- never the HTTP call -- so a
  # ShipStation outage cannot raise inside that transaction and roll back an
  # order Square has already charged. Same reasoning as Solidus's own
  # confirmation-email subscriber.
  class ShipstationSubscriber
    include Omnes::Subscriber

    handle :order_finalized,
      with: :push_to_shipstation,
      id: :nsb_shipstation_push

    def push_to_shipstation(event)
      order = event[:order]
      Nsb::PushOrderToShipstationJob.perform_later(order)
    rescue => error
      # Even a failure to ENQUEUE must not break checkout. Log it; the operator
      # can re-push from the admin.
      Rails.logger.error("[shipstation] could not enqueue push for #{order&.number}: #{error.message}")
    end
  end
end
