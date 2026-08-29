# frozen_string_literal: true

require "net/http"

module Nsb
  # A one-shot diagnostic for the Google Address Validation setup.
  #
  # Deliberately NOT Nsb::AddressValidator. That class exists to never break the
  # application form, so it swallows every failure and returns `skipped` -- which
  # is right in production and useless when you are trying to find out why
  # nothing is being validated. This one says exactly what happened.
  #
  # Run it once from a Render shell after setting the environment variable:
  #
  #   bin/rails nsb:address:check
  #
  # Never prints the key.
  class AddressValidationCheck
    # A real, deliverable address, so a healthy setup returns a confident verdict
    # rather than an ambiguous one. The operator's own town.
    SAMPLE = "2564 N Main St, Conway, SC 29526"

    Report = Struct.new(:ok, :headline, :details, keyword_init: true)

    def call
      key = Nsb::AddressValidator.api_key
      return missing_key unless key

      response = perform(key)
      return unreachable(response) if response.is_a?(Exception)

      interpret(response)
    end

    private

    def missing_key
      Report.new(
        ok: false,
        headline: "GOOGLE_ADDRESS_VALIDATION_API_KEY is not set",
        details: [
          "The form still works -- addresses just are not checked.",
          "Set the variable in Render's environment, then run this again."
        ]
      )
    end

    def perform(key)
      uri = URI("#{Nsb::AddressValidator::ENDPOINT}?key=#{key}")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      request.body = { address: { regionCode: "US", addressLines: [ SAMPLE ] } }.to_json

      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
        http.request(request)
      end
    rescue StandardError => e
      e
    end

    def unreachable(error)
      Report.new(
        ok: false,
        headline: "Could not reach Google (#{error.class})",
        details: [
          error.message,
          "The form is unaffected: applicants go straight through when this happens."
        ]
      )
    end

    def interpret(response)
      body = JSON.parse(response.body) rescue {}
      message = body.dig("error", "message")

      case response.code.to_i
      when 200 then success(body)
      when 400 then failure("Google rejected the request (400)", [ message, "Usually a malformed request rather than a setup problem." ])
      when 403 then failure("Key rejected or API not enabled (403)", [
        message,
        "Check: the Address Validation API is enabled on the project, and any",
        "key restrictions allow it. An IP-restricted key will fail from Render."
      ])
      when 429 then failure("Quota exhausted (429)", [
        message,
        "Raise the daily cap, or leave it -- applicants are never blocked by this."
      ])
      else failure("Unexpected response (#{response.code})", [ message || response.body.to_s[0, 200] ])
      end
    end

    def success(body)
      verdict = body.dig("result", "verdict") || {}
      formatted = body.dig("result", "address", "formattedAddress")

      Report.new(
        ok: true,
        headline: "Working",
        details: [
          "Sent:      #{SAMPLE}",
          "Google:    #{formatted}",
          "Complete:  #{verdict['addressComplete'] ? 'yes' : 'no'}",
          "Address validation is live on the application form."
        ]
      )
    end

    def failure(headline, details)
      Report.new(ok: false, headline: headline, details: details.compact)
    end
  end
end
