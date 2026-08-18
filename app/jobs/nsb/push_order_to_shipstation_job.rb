# frozen_string_literal: true

module Nsb
  # Pushes a completed order to ShipStation, out of band.
  #
  # THE RULE (CLAUDE.md): an order must complete even if ShipStation is
  # unreachable. Fulfilment is a downstream concern; the customer's order is the
  # source of truth. This runs as a job precisely so a ShipStation outage cannot
  # roll back or block a checkout that Square has already charged -- the same
  # principle as the order confirmation email.
  #
  # The result is recorded on the order's admin_metadata so a failed push is
  # visible in the admin rather than only in a log nobody reads.
  class PushOrderToShipstationJob < ApplicationJob
    queue_as :default

    # Transient problems: back off and try again. 5 attempts over a few minutes
    # covers a brief outage without hammering them.
    retry_on Nsb::Shipstation::Client::RetryableError,
      wait: :polynomially_longer, attempts: 5

    # A malformed address or bad credentials will never succeed. Record it and
    # stop, rather than retrying four more times and burying the reason.
    discard_on Nsb::Shipstation::Client::PermanentError do |job, error|
      order = job.arguments.first
      job.send(:record_failure, order, error) if order.is_a?(Spree::Order)
    end

    def perform(order)
      config = Nsb::Shipstation::Configuration.new
      return record_skipped(order, "ShipStation not configured") unless config.enabled?

      payload = Nsb::Shipstation::OrderPayload.new(order, config: config).to_h
      response = Nsb::Shipstation::Client.new(config: config).create_order(payload)

      record_success(order, response)
    rescue Nsb::Shipstation::Client::RetryableError => error
      # Record before re-raising so the admin shows the in-progress failure even
      # while retries continue.
      record_failure(order, error, retrying: true)
      raise
    end

    private

    def record_success(order, response)
      write_status(order,
        state: "pushed",
        shipstation_order_id: response["orderId"],
        pushed_at: Time.current.iso8601,
        error: nil)
      Rails.logger.info("[shipstation] pushed order #{order.number} (id #{response['orderId']})")
    end

    def record_failure(order, error, retrying: false)
      write_status(order,
        state: retrying ? "retrying" : "failed",
        error: error.message.to_s.first(500),
        failed_at: Time.current.iso8601)
      Rails.logger.error(
        "[shipstation] #{retrying ? 'retrying' : 'FAILED'} order #{order.number}: #{error.message}"
      )
    end

    def record_skipped(order, reason)
      write_status(order, state: "skipped", error: reason)
      Rails.logger.warn("[shipstation] skipped order #{order.number}: #{reason}")
    end

    # update_column rather than update!: this must never fail on an unrelated
    # order validation, and must not fire callbacks on an order that is already
    # complete.
    def write_status(order, **attrs)
      metadata = (order.admin_metadata || {}).merge("shipstation" => attrs.stringify_keys.compact)
      order.update_column(:admin_metadata, metadata)
    end
  end
end
