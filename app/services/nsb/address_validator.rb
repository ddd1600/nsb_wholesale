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

    # How precisely Google matched the address. PREMISE is a building,
    # SUB_PREMISE a unit within one. Anything coarser -- ROUTE, BLOCK, OTHER --
    # means it found the street or the area but not the address, which is what
    # an invented street number looks like.
    CONFIRMED_GRANULARITY = %w[PREMISE SUB_PREMISE].freeze

    # Google's verdict vocabulary, reduced to the three cases the form acts on.
    #
    # formatted_address is kept for nsb:address:check, which prints it as
    # evidence. The form deliberately does not show it -- see the comment in
    # wholesale_applications/new.html.erb.
    Result = Struct.new(:status, :input, :formatted_address, :message, keyword_init: true) do
      def confirmed? = status == :confirmed
      def suspect? = status == :suspect
      def skipped? = status == :skipped

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

      interpret(response, address)
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

    def interpret(body, input = nil)
      result = body["result"] || {}
      verdict = result["verdict"] || {}
      formatted = result.dig("address", "formattedAddress")

      reasons = problems(result, verdict)

      if reasons.empty?
        Result.new(status: :confirmed, input: input, formatted_address: formatted)
      else
        Result.new(status: :suspect, input: input, formatted_address: formatted, message: reasons.first)
      end
    end

    # Why we would not just accept this address.
    #
    # addressComplete alone is not enough, which is how an invented street
    # number on a real street got through: nothing is missing from the address,
    # so Google calls it complete, while separately reporting that it could not
    # confirm the number. The unconfirmed-components flag and the granularity
    # are what catch that.
    #
    # hasInferredComponents is deliberately NOT here. Google infers ZIP+4 and
    # county on perfectly good addresses, so treating it as a problem would
    # query almost every submission.
    def problems(result, verdict)
      unresolved = result.dig("address", "unresolvedTokens").presence
      missing = result.dig("address", "missingComponentTypes").presence
      granularity = verdict["validationGranularity"]

      problems = []
      problems << "We could not find part of this address: #{unresolved.join(', ')}" if unresolved
      problems << "This address looks incomplete (missing #{missing.join(', ')})" if missing
      problems << "We could not confirm every part of this address" if verdict["hasUnconfirmedComponents"]

      unless CONFIRMED_GRANULARITY.include?(granularity)
        problems << "We could not match this to a specific building"
      end

      problems << "We could not confirm this address" unless verdict["addressComplete"]
      problems
    end
  end
end
