# frozen_string_literal: true

module Nsb
  module Square
    # Receives webhook events from Square.
    #
    # Inherits ActionController::Base rather than StoreController: this is a
    # machine-to-machine endpoint with no session, no current order, no locale
    # and no layout, and it must not pick up the wholesale account gate.
    #
    # Authentication is the signature, and nothing else. Square is not logged in
    # and has no CSRF token, so forgery protection is skipped -- which is
    # precisely why Nsb::Square::WebhookSignature has to be right.
    class WebhooksController < ActionController::Base
      skip_forgery_protection

      # Square retries on any non-2xx, so the status codes here are the retry
      # policy:
      #
      #   200 -- handled, or deliberately ignored. Do not send it again.
      #   401 -- signature did not verify. Not ours; nothing to retry.
      #   500 -- we broke. Please do send it again.
      def create
        raw_body = request.raw_post

        unless signature.configured?
          # Fail closed. An unset key must never mean "accept everything".
          Rails.logger.error("[square-webhook] SQUARE_WEBHOOK_SIGNATURE_KEY is not set; rejecting")
          return head :unauthorized
        end

        unless signature.valid?(raw_body, request.headers["HTTP_X_SQUARE_HMACSHA256_SIGNATURE"])
          Rails.logger.warn("[square-webhook] rejected an event with an invalid signature")
          return head :unauthorized
        end

        event = JSON.parse(raw_body)
        handle(event)
        head :ok
      rescue JSON::ParserError => error
        # Verified as Square's, but unreadable. Retrying will not help.
        Rails.logger.error("[square-webhook] could not parse a verified event: #{error.message}")
        head :ok
      rescue => error
        # Let Square retry, and make sure a person hears about it: a refund that
        # silently fails to record is the exact problem this endpoint exists to
        # fix.
        Rails.logger.error("[square-webhook] #{error.class}: #{error.message}")
        Sentry.capture_exception(error) if defined?(Sentry) && Sentry.initialized?
        head :internal_server_error
      end

      private

      # Only refunds are acted on. Other event types are acknowledged rather
      # than rejected, so subscribing to something extra in Square's dashboard
      # does not produce an endless retry loop here.
      def handle(event)
        type = event["type"]

        case type
        when "refund.created", "refund.updated"
          payload = event.dig("data", "object", "refund")
          if payload.blank?
            Rails.logger.error("[square-webhook] #{type} carried no refund object")
            return
          end

          result = Nsb::Square::RefundReconciler.new.call(payload)
          Rails.logger.info("[square-webhook] #{type} -> #{result}")
        else
          Rails.logger.info("[square-webhook] ignoring #{type.inspect}")
        end
      end

      def signature
        @signature ||= Nsb::Square::WebhookSignature.new
      end
    end
  end
end
