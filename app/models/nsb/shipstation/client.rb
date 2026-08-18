# frozen_string_literal: true

require "net/http"

module Nsb
  module Shipstation
    # Thin HTTP client for ShipStation API V1.
    #
    # Errors are classified into two kinds, because the caller treats them very
    # differently:
    #
    #   RetryableError  - timeouts, connection failures, 429s and 5xx. The push
    #                     may yet succeed; the job retries with backoff.
    #   PermanentError  - 4xx other than 429, e.g. a malformed address or bad
    #                     credentials. Retrying will not help; surface it to the
    #                     operator instead of burning retries.
    #
    # Neither is ever raised into checkout: the caller is a background job.
    class Client
      class Error < StandardError; end
      class RetryableError < Error; end
      class PermanentError < Error; end

      # Generous but bounded. ShipStation is not in the customer's path, so a
      # slow response costs nothing except job time.
      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 30

      def initialize(config: Nsb::Shipstation::Configuration.new)
        @config = config
      end

      # Creates or updates an order. ShipStation matches on orderKey, so this is
      # idempotent -- pushing the same order twice updates it rather than
      # duplicating it in the operator's queue.
      def create_order(payload)
        post("/orders/createorder", payload)
      end

      private

      attr_reader :config

      def post(path, payload)
        key, secret = config.credentials!
        uri = URI.join(config.base_url, path)

        request = Net::HTTP::Post.new(uri)
        request.basic_auth(key, secret)
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"
        request.body = JSON.generate(payload)

        response = perform(uri, request)
        handle(response)
      end

      def perform(uri, request)
        Net::HTTP.start(
          uri.host, uri.port,
          use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT
        ) { |http| http.request(request) }
      rescue Net::OpenTimeout, Net::ReadTimeout => error
        raise RetryableError, "Timed out talking to ShipStation: #{error.class}"
      rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, OpenSSL::SSL::SSLError => error
        raise RetryableError, "Could not reach ShipStation: #{error.class}: #{error.message}"
      end

      def handle(response)
        code = response.code.to_i

        case code
        when 200..299
          parse(response.body)
        when 429
          # ShipStation V1 rate-limits per minute. Irrelevant at one order a
          # day, but a burst during a re-import would hit it.
          raise RetryableError, "ShipStation rate limit hit (429)"
        when 500..599
          raise RetryableError, "ShipStation server error (#{code})"
        else
          raise PermanentError, "ShipStation rejected the order (#{code}): #{error_message(response.body)}"
        end
      end

      def parse(body)
        body.present? ? JSON.parse(body) : {}
      rescue JSON::ParserError
        {}
      end

      # ShipStation returns {"Message": "..."} or {"ExceptionMessage": "..."}.
      def error_message(body)
        parsed = JSON.parse(body.to_s) rescue nil
        return body.to_s.first(300) unless parsed.is_a?(Hash)

        parsed["ExceptionMessage"].presence || parsed["Message"].presence || body.to_s.first(300)
      end
    end
  end
end
