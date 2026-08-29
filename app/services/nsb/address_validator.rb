# frozen_string_literal: true

require "net/http"

module Nsb
  # Checks a postal address against Google's Address Validation API.
  #
  # Advisory, never blocking. Google flags plenty of real addresses as
  # unconfirmed -- new builds, rural routes, suites it does not know -- and a
  # wholesale application is worth more than a tidy address field. So the caller
  # gets a verdict to show the applicant once, and the applicant can submit
  # anyway.
  #
  # Configured by GOOGLE_ADDRESS_VALIDATION_API_KEY. With no key this returns
  # `skipped` and the form behaves exactly as it did before, which is also what
  # happens in development and test. Never put the key in the repo; it belongs in
  # Render's environment.
  #
  # Called server-side rather than from the browser so the key is never shipped
  # to a page.
  class AddressValidator
    ENDPOINT = "https://addressvalidation.googleapis.com/v1:validateAddress"
    TIMEOUT = 5

    # Google's verdict vocabulary, reduced to the three cases the form acts on.
    Result = Struct.new(:status, :formatted_address, :message, keyword_init: true) do
      def confirmed? = status == :confirmed
      def suspect? = status == :suspect
      def skipped? = status == :skipped
      def suggestion? = suspect? && formatted_address.present?
    end

    def self.api_key = ENV["GOOGLE_ADDRESS_VALIDATION_API_KEY"].presence

    def self.configured? = api_key.present?

    def initialize(logger: Rails.logger)
      @logger = logger
    end

    def call(address)
      return skipped if address.blank? || !self.class.configured?

      response = post(address)
      return skipped unless response

      interpret(response)
    rescue StandardError => e
      # A validation outage must never cost an application. Log it and wave the
      # address through.
      @logger.warn("[address-validation] #{e.class}: #{e.message}")
      skipped
    end

    private

    def skipped = Result.new(status: :skipped)

    def post(address)
      uri = URI("#{ENDPOINT}?key=#{self.class.api_key}")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      request.body = {
        address: { regionCode: "US", addressLines: address.to_s.lines.map(&:strip).reject(&:blank?) }
      }.to_json

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                 open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        @logger.warn("[address-validation] #{response.code}: #{response.body.to_s[0, 200]}")
        return nil
      end

      JSON.parse(response.body)
    end

    def interpret(body)
      result = body["result"] || {}
      verdict = result["verdict"] || {}
      formatted = result.dig("address", "formattedAddress")

      # Google's own definition of "we found this and it is complete enough to
      # deliver to". Anything short of it is worth showing the applicant once.
      complete = verdict["addressComplete"]
      unresolved = result.dig("address", "unresolvedTokens").presence
      missing = result.dig("address", "missingComponentTypes").presence

      if complete && unresolved.nil? && missing.nil?
        Result.new(status: :confirmed, formatted_address: formatted)
      else
        Result.new(status: :suspect, formatted_address: formatted, message: reason(missing, unresolved))
      end
    end

    def reason(missing, unresolved)
      return "We could not find part of this address: #{unresolved.join(', ')}" if unresolved
      return "This address looks incomplete (missing #{missing.join(', ')})" if missing

      "We could not confirm this address"
    end
  end
end
