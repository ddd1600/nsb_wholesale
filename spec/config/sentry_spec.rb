# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# Error monitoring is only useful if it reports the right things and none of the
# wrong ones. This app handles wholesale customers' names, addresses and order
# history, and card tokens pass through checkout params -- an error tracker is
# not the place for any of that.
RSpec.describe "Sentry configuration" do
  it "stays inert without a DSN, so nothing is reported from a laptop" do
    expect(Sentry.initialized?).to be(false)
  end

  describe "the parameter filter it relies on" do
    subject(:filter) { ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

    # Regression: "gateway_payment_profile_id" matches none of Rails' default
    # patterns -- not "token", not "secret" -- so Square's card token was being
    # written to logs in clear.
    it "filters Square's card token" do
      filtered = filter.filter("gateway_payment_profile_id" => "cnon:CARD-TOKEN")

      expect(filtered["gateway_payment_profile_id"]).to eq("[FILTERED]")
    end

    it "filters it when nested inside checkout params, as it actually arrives" do
      filtered = filter.filter(
        "payment_source" => { "3" => { "gateway_payment_profile_id" => "cnon:CARD-TOKEN" } }
      )

      expect(filtered.dig("payment_source", "3", "gateway_payment_profile_id")).to eq("[FILTERED]")
    end

    it "keeps the last four digits, which support needs" do
      filtered = filter.filter("last_digits" => "1111")

      expect(filtered["last_digits"]).to eq("1111")
    end

    it "filters integration credentials" do
      filtered = filter.filter(
        "api_key" => "k", "access_token" => "t", "refresh_token" => "r", "client_secret" => "s"
      )

      expect(filtered.values.uniq).to eq(["[FILTERED]"])
    end

    it "filters passwords and customer email addresses" do
      filtered = filter.filter("password" => "hunter2", "email" => "buyer@example.com")

      expect(filtered["password"]).to eq("[FILTERED]")
      expect(filtered["email"]).to eq("[FILTERED]")
    end
  end
end
