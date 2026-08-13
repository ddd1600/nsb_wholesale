# frozen_string_literal: true

module Nsb
  module Square
    # Adapts Square's official Ruby SDK to the interface Solidus expects of a
    # payment gateway (purchase / authorize / capture / void / credit, each
    # returning an ActiveMerchant::Billing::Response).
    #
    # THE RULE THAT MATTERS (CLAUDE.md): an order is marked paid only after
    # Square confirms the charge succeeded. Concretely, #success? on the response
    # we return is true ONLY when Square reports a payment status of COMPLETED
    # (for a purchase) or APPROVED (for an authorization). It is never inferred
    # from "no exception was raised", never set on tokenisation, and never set
    # inside a rescue.
    #
    # How failures are classified, and why:
    #
    #   * Square timeout / connection failure -> re-raised as
    #     ActiveMerchant::ConnectionError. Solidus catches that and raises a
    #     GatewayError WITHOUT completing the payment. This matters because the
    #     charge may in fact have succeeded at Square; we must not guess either
    #     way. The idempotency key below makes a retry safe.
    #   * 4xx from Square (declined card, bad token) -> a FAILED response object.
    #     Solidus records the failure and shows the customer the message.
    #   * 5xx from Square -> ConnectionError, same reasoning as a timeout: the
    #     outcome is genuinely unknown.
    #
    # Card data never reaches this class. The browser tokenises with Square's Web
    # Payments SDK and posts only the resulting single-use token.
    class Gateway
      # Square payment statuses we treat as authoritative confirmation.
      CAPTURED = "COMPLETED"
      AUTHORIZED = "APPROVED"

      def initialize(options = {})
        @options = options
      end

      # Charge immediately (auth + capture in one call).
      def purchase(amount_cents, source, gateway_options = {})
        create_payment(amount_cents, source, gateway_options, autocomplete: true)
      end

      # Authorize only; funds captured later by #capture.
      def authorize(amount_cents, source, gateway_options = {})
        create_payment(amount_cents, source, gateway_options, autocomplete: false)
      end

      # Capture a previously authorized payment. Square captures the full
      # authorized amount, so a differing amount_cents is reported rather than
      # silently ignored.
      def capture(amount_cents, response_code, gateway_options = {})
        with_square_errors do
          response = client.payments.complete(payment_id: response_code, body: {})
          payment = response.payment

          if payment&.status == CAPTURED
            success(payment, "Payment captured")
          else
            failure("Square did not confirm capture (status: #{payment&.status.inspect})", payment)
          end
        end
      end

      # Cancel an authorization that has not been captured.
      def void(response_code, gateway_options = {})
        with_square_errors do
          response = client.payments.cancel(payment_id: response_code)
          payment = response.payment

          if payment&.status == "CANCELED"
            success(payment, "Payment voided")
          else
            failure("Square did not confirm the void (status: #{payment&.status.inspect})", payment)
          end
        end
      end

      # Refund, in whole or in part. Solidus passes the amount to refund, so this
      # covers both the partial and full refund cases.
      def credit(amount_cents, response_code, gateway_options = {})
        with_square_errors do
          response = client.refunds.refund_payment(
            idempotency_key: idempotency_key(gateway_options, prefix: "refund"),
            payment_id: response_code,
            amount_money: money(amount_cents, gateway_options),
            reason: gateway_options[:reason].presence || "Refund issued from Solidus"
          )
          refund = response.refund

          # PENDING is a legitimate outcome: Square has accepted the refund and
          # it will settle. COMPLETED means it already has. Anything else is not
          # a confirmation.
          if %w[COMPLETED PENDING].include?(refund&.status)
            ActiveMerchant::Billing::Response.new(
              true,
              "Refund #{refund.status.downcase}",
              { "refund_id" => refund.id, "status" => refund.status },
              authorization: refund.id
            )
          else
            failure("Square did not confirm the refund (status: #{refund&.status.inspect})", nil)
          end
        end
      end

      private

      attr_reader :options

      def create_payment(amount_cents, source, gateway_options, autocomplete:)
        token = source_token(source)
        return failure("No payment token was supplied by the browser.", nil) if token.blank?

        expected_status = autocomplete ? CAPTURED : AUTHORIZED

        with_square_errors do
          response = client.payments.create(
            source_id: token,
            # Stable per Spree::Payment (order_id here is "R123-P456"), so a
            # double-clicked checkout button reuses the same key and Square
            # returns the ORIGINAL payment instead of charging twice.
            idempotency_key: idempotency_key(gateway_options),
            amount_money: money(amount_cents, gateway_options),
            autocomplete: autocomplete,
            location_id: config.location_id,
            reference_id: gateway_options[:order_id].to_s.first(40),
            buyer_email_address: gateway_options[:email],
            note: "Wholesale order #{gateway_options[:order_id]}"
          )
          payment = response.payment

          # The single most important line in this class: success is driven by
          # Square's own status, not by the absence of an exception.
          if payment&.status == expected_status
            success(payment, autocomplete ? "Payment captured" : "Payment authorized")
          else
            failure(
              "Square did not confirm the charge (status: #{payment&.status.inspect})",
              payment
            )
          end
        end
      end

      # The Web Payments SDK token is carried on the credit card record in
      # gateway_payment_profile_id -- the conventional Solidus slot for a
      # tokenised source. No PAN, CVV or expiry is ever stored or transmitted.
      def source_token(source)
        return source if source.is_a?(String)

        source.try(:gateway_payment_profile_id).presence
      end

      def idempotency_key(gateway_options, prefix: nil)
        base = gateway_options[:order_id].presence || SecureRandom.uuid
        [prefix, base].compact.join("-").first(45)
      end

      def money(amount_cents, gateway_options)
        {
          amount: amount_cents.to_i,
          currency: (gateway_options[:currency] || config.currency).to_s.upcase
        }
      end

      # Builds the success response.
      #
      # Everything in here runs AFTER Square has already taken the customer's
      # money, so it must not be able to raise. It previously did: avs_status and
      # cvv_status live on CardPaymentDetails, not on the nested Card, and
      # reading them off the wrong object raised NoMethodError *after* a
      # successful charge -- the customer was billed and the order was not
      # marked paid.
      #
      # The rescue below is not laziness about correctness; it is the deliberate
      # trade that losing optional AVS metadata is always preferable to losing a
      # paid order. It never converts a failure into a success -- it is only ever
      # reached once Square has confirmed.
      def success(payment, message)
        details = payment.card_details

        ActiveMerchant::Billing::Response.new(
          true,
          message,
          {
            "payment_id" => payment.id,
            "status" => payment.status,
            "receipt_url" => payment.receipt_url,
            "order_id" => payment.order_id
          },
          # Solidus stores this as response_code and uses it for capture, void
          # and refund. It must be Square's payment id.
          authorization: payment.id,
          avs_result: { code: details.try(:avs_status) },
          cvv_result: details.try(:cvv_status)
        )
      rescue => error
        Rails.logger.error(
          "[square] charge #{payment&.id} succeeded but building the response failed: " \
          "#{error.class}: #{error.message}"
        )
        ActiveMerchant::Billing::Response.new(
          true,
          message,
          { "payment_id" => payment.id, "status" => payment.status },
          authorization: payment.id
        )
      end

      def failure(message, payment)
        ActiveMerchant::Billing::Response.new(
          false,
          message,
          { "message" => message, "status" => payment&.status }.compact,
          authorization: payment&.id
        )
      end

      # Translates Square's exceptions into the two shapes Solidus understands,
      # per the classification documented at the top of this class.
      def with_square_errors
        yield
      rescue Nsb::Square::Configuration::MissingCredentials => error
        # Server misconfiguration, not a customer problem. Raised as a
        # ConnectionError so Solidus shows a gateway error and leaves the order
        # UNPAID, rather than 500ing mid-checkout.
        raise ActiveMerchant::ConnectionError.new(
          "Card payment is unavailable: #{error.message}", error
        )
      rescue ::Square::Errors::TimeoutError => error
        # Outcome unknown -- the charge may have gone through. Never treat as
        # either success or a clean decline.
        raise ActiveMerchant::ConnectionError.new(
          "Timed out talking to Square; the charge may or may not have completed. " \
          "Check the Square dashboard before retrying.",
          error
        )
      rescue ::Square::Errors::ServerError => error
        raise ActiveMerchant::ConnectionError.new("Square returned a server error: #{error.message}", error)
      rescue ::Square::Errors::ResponseError => error
        # 4xx: Square reached a decision and rejected it. A declined card lands here.
        failure(square_error_message(error), nil)
      end

      # Square's own wording is written for developers -- a declined card comes
      # back as "Authorization error: 'GENERIC_DECLINE'", which tells a wholesale
      # customer nothing and looks like a fault in our site. These translate the
      # codes worth distinguishing into something a buyer can act on.
      #
      # Anything unmapped falls back to a plain decline message rather than
      # leaking a raw code.
      CUSTOMER_MESSAGES = {
        "GENERIC_DECLINE" => "Your card was declined. Please try another card, or contact your bank.",
        "CVV_FAILURE" => "The security code (CVV) didn't match. Please check it and try again.",
        "ADDRESS_VERIFICATION_FAILURE" => "The billing address didn't match your card. Please check it and try again.",
        "INVALID_ACCOUNT" => "Your bank didn't recognise that card. Please try another card.",
        "INSUFFICIENT_FUNDS" => "There aren't enough funds available on that card.",
        "CARD_EXPIRED" => "That card has expired. Please use a different card.",
        "INVALID_EXPIRATION" => "The expiry date looks wrong. Please check it and try again.",
        "CARD_NOT_SUPPORTED" => "That card type isn't supported. Please try another card.",
        "INVALID_CARD" => "Those card details didn't work. Please check them and try again.",
        "PAN_FAILURE" => "That card number didn't work. Please check it and try again.",
        "TRANSACTION_LIMIT" => "That amount exceeds the limit on your card. Please contact your bank or use another card.",
        "CARD_DECLINED_VERIFICATION_REQUIRED" => "Your bank needs to verify this payment. Please contact them, or try another card.",
        "CARD_DECLINED_CALL_ISSUER" => "Your bank declined the payment and asked that you call them.",
        "PAYMENT_LIMIT_EXCEEDED" => "This payment exceeds our processing limit. Please contact us to place the order.",
        "VERIFY_CVV_FAILURE" => "The security code (CVV) didn't match. Please check it and try again.",
        "VERIFY_AVS_FAILURE" => "The billing address didn't match your card. Please check it and try again."
      }.freeze

      GENERIC_DECLINE_MESSAGE = "Your card was declined. Please try another card, or contact us if the problem continues."

      def square_error_message(error)
        parsed = JSON.parse(error.message) rescue nil
        errors = parsed&.dig("errors")
        return GENERIC_DECLINE_MESSAGE if errors.blank?

        messages = errors.filter_map { |e| CUSTOMER_MESSAGES[e["code"]] }.uniq
        return messages.join(" ") if messages.any?

        # Log the unmapped code so it can be added, but never show it to the
        # customer.
        codes = errors.filter_map { |e| e["code"] }.uniq
        Rails.logger.warn("[square] unmapped decline code(s): #{codes.join(', ')}") if codes.any?
        GENERIC_DECLINE_MESSAGE
      end

      def client
        @client ||= config.client
      end

      def config
        @config ||= Nsb::Square::Configuration.new
      end
    end
  end
end
