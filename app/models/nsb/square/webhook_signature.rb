# frozen_string_literal: true

module Nsb
  module Square
    # Verifies that a webhook request really came from Square.
    #
    # This is the only thing standing between a stranger with our URL and a POST
    # that marks orders refunded. Everything downstream trusts it.
    #
    # The algorithm is Square's, from their webhook documentation: HMAC-SHA256
    # over the notification URL concatenated with the raw request body, keyed by
    # the subscription's signature key, Base64-encoded, and compared against the
    # x-square-hmacsha256-signature header.
    #
    # Not delegated to the SDK's SquareLegacy::WebhooksHelper, deliberately. It
    # builds the same digest, but finishes with `hash_base64 == signature_header`
    # -- a plain string comparison that short-circuits on the first differing
    # byte. Square's own documentation warns about exactly this ("a malicious
    # agent can compromise your notification endpoint by using a timing analysis
    # attack") and their Ruby helper does not follow that advice. The comparison
    # here is constant-time.
    class WebhookSignature
      HEADER = "HTTP_X_SQUARE_HMACSHA256_SIGNATURE"

      class MissingKey < StandardError; end

      def initialize(config: Nsb::Square::Configuration.new)
        @config = config
      end

      # The URL must match what is registered in Square byte for byte -- Square
      # signs the URL it was configured with, not the one the request happened
      # to arrive on. Configurable rather than derived from the request because
      # a proxy that rewrites scheme or host would silently break every webhook,
      # and the failure looks like "Square stopped sending" rather than a
      # mismatch.
      def notification_url
        ENV["SQUARE_WEBHOOK_URL"].presence ||
          "https://#{mailer_host}/square/webhooks"
      end

      def signature_key
        ENV["SQUARE_WEBHOOK_SIGNATURE_KEY"].presence
      end

      def configured?
        signature_key.present?
      end

      # True only for a request Square could have produced.
      def valid?(raw_body, signature_header)
        raise MissingKey, "SQUARE_WEBHOOK_SIGNATURE_KEY is not set" if signature_key.blank?
        return false if raw_body.nil? || signature_header.blank?

        expected = digest(raw_body)

        # Length is compared first because secure_compare raises on differing
        # lengths; doing it this way leaks only the length, which the header
        # already reveals.
        return false unless expected.bytesize == signature_header.bytesize

        ActiveSupport::SecurityUtils.secure_compare(expected, signature_header)
      end

      private

      def digest(raw_body)
        payload = "#{notification_url}#{raw_body}".dup.force_encoding("UTF-8")
        key = signature_key.dup.force_encoding("UTF-8")

        Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", key, payload))
      end

      def mailer_host
        Spree::Store.default&.url.presence ||
          ActionMailer::Base.default_url_options[:host].presence ||
          raise(MissingKey, "Set SQUARE_WEBHOOK_URL, or Spree::Store#url")
      end
    end
  end
end
