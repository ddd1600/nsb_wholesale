# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

RSpec.describe Nsb::AddressValidationCheck do
  subject(:check) { described_class.new }

  def stub_response(status:, body:)
    response = instance_double(Net::HTTPResponse, code: status.to_s, body: body)
    allow(Net::HTTP).to receive(:start).and_return(response)
  end

  def with_key(&) = ClimateControl.modify(GOOGLE_ADDRESS_VALIDATION_API_KEY: "test-key", &)

  it "says so when the key is missing, and that the form still works" do
    ClimateControl.modify(GOOGLE_ADDRESS_VALIDATION_API_KEY: nil) do
      report = check.call

      expect(report.ok).to be(false)
      expect(report.headline).to include("not set")
      expect(report.details.join(" ")).to include("form still works")
    end
  end

  it "reports a working setup with what Google made of the address" do
    with_key do
      stub_response(status: 200, body: {
        result: { verdict: { addressComplete: true },
                  address: { formattedAddress: "2564 N Main St, Conway, SC 29526, USA" } }
      }.to_json)

      report = check.call

      expect(report.ok).to be(true)
      expect(report.details.join(" ")).to include("2564 N Main St, Conway, SC 29526, USA")
    end
  end

  it "names the likely cause of a 403 rather than just the code" do
    with_key do
      stub_response(status: 403, body: { error: { message: "API key not valid" } }.to_json)

      report = check.call

      expect(report.ok).to be(false)
      expect(report.headline).to include("403")
      expect(report.details.join(" ")).to include("Address Validation API is enabled")
    end
  end

  it "distinguishes an exhausted quota" do
    with_key do
      stub_response(status: 429, body: { error: { message: "Quota exceeded" } }.to_json)

      expect(check.call.headline).to include("Quota exhausted")
    end
  end

  it "reports an unreachable network without raising" do
    with_key do
      allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout, "timed out")

      report = check.call

      expect(report.ok).to be(false)
      expect(report.headline).to include("Could not reach Google")
    end
  end

  it "never prints the key" do
    with_key do
      stub_response(status: 403, body: { error: { message: "API key not valid" } }.to_json)

      expect([ check.call.headline, *check.call.details ].join(" ")).not_to include("test-key")
    end
  end
end
