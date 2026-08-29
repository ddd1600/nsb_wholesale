# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

RSpec.describe Nsb::AddressValidator do
  subject(:validator) { described_class.new(logger: Logger.new(IO::NULL)) }

  let(:address) { "12 Front Street, Conway, SC 29526" }

  def stub_google(status:, body: "{}")
    response = instance_double(
      Net::HTTPResponse, code: status.to_s, body: body,
      is_a?: false
    )
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(status == 200)
    allow(Net::HTTP).to receive(:start).and_return(response)
  end

  def with_key(&block)
    ClimateControl.modify(GOOGLE_ADDRESS_VALIDATION_API_KEY: "test-key", &block)
  end

  describe "without an API key" do
    it "skips, so the form behaves as it did before the integration existed" do
      ClimateControl.modify(GOOGLE_ADDRESS_VALIDATION_API_KEY: nil) do
        expect(Net::HTTP).not_to receive(:start)
        expect(validator.call(address)).to be_skipped
      end
    end
  end

  describe "with an API key" do
    it "confirms an address Google resolves down to the building" do
      with_key do
        stub_google(status: 200, body: {
          result: { verdict: { addressComplete: true, validationGranularity: "PREMISE" },
                    address: { formattedAddress: "12 Front St, Conway, SC 29526, USA" } }
        }.to_json)

        result = validator.call(address)

        expect(result).to be_confirmed
        expect(result.formatted_address).to eq("12 Front St, Conway, SC 29526, USA")
      end
    end

    it "accepts an address Google tidied up but still placed exactly" do
      # Inferring ZIP+4 or county is routine on good addresses. Treating that as
      # a problem would query almost every submission.
      with_key do
        stub_google(status: 200, body: {
          result: { verdict: { addressComplete: true, validationGranularity: "PREMISE",
                               hasInferredComponents: true },
                    address: { formattedAddress: "12 Front St, Conway, SC 29526-1234, USA" } }
        }.to_json)

        expect(validator.call(address)).to be_confirmed
      end
    end

    # The bug this logic exists for: a made-up street number on a real street.
    # Nothing is missing, so Google reports addressComplete, and an earlier
    # version accepted it on that alone.
    it "flags an invented street number even though the address is complete" do
      with_key do
        stub_google(status: 200, body: {
          result: { verdict: { addressComplete: true, validationGranularity: "ROUTE",
                               hasUnconfirmedComponents: true },
                    address: { formattedAddress: "Front St, Conway, SC 29526, USA" } }
        }.to_json)

        result = validator.call(address)

        expect(result).to be_suspect
        expect(result.message).to include("could not confirm")
      end
    end

    # The operator entered "999 Chapin Circle, Myrtle Beach, SC 29572", was
    # asked "did you mean 999 Chapin Circle, Myrtle Beach, SC 29572, USA?",
    # typed exactly that, and was let through. Google had not corrected
    # anything; it appended the country to an address it could not confirm.
    it "does not offer a suggestion that is the input with a country appended" do
      with_key do
        stub_google(status: 200, body: {
          result: { verdict: { addressComplete: true, validationGranularity: "ROUTE",
                               hasUnconfirmedComponents: true },
                    address: { formattedAddress: "999 Chapin Circle, Myrtle Beach, SC 29572, USA" } }
        }.to_json)

        result = validator.call("999 Chapin Circle, Myrtle Beach, SC 29572")

        expect(result).to be_suspect
        expect(result.suggestion?).to be(false)
      end
    end

    it "still offers a suggestion when Google genuinely corrected something" do
      with_key do
        stub_google(status: 200, body: {
          result: { verdict: { addressComplete: true, validationGranularity: "ROUTE",
                               hasUnconfirmedComponents: true },
                    address: { formattedAddress: "12 Front Street, Conway, SC 29526, USA" } }
        }.to_json)

        result = validator.call("12 Frunt St, Conway, SC 29526")

        expect(result.suggestion?).to be(true)
      end
    end

    it "ignores case, punctuation and spacing when deciding that" do
      with_key do
        stub_google(status: 200, body: {
          result: { verdict: { addressComplete: true, validationGranularity: "ROUTE",
                               hasUnconfirmedComponents: true },
                    address: { formattedAddress: "999 CHAPIN CIRCLE, MYRTLE BEACH, SC  29572" } }
        }.to_json)

        expect(validator.call("999 chapin circle myrtle beach sc 29572").suggestion?).to be(false)
      end
    end

    it "flags an address matched only to a street or an area" do
      with_key do
        stub_google(status: 200, body: {
          result: { verdict: { addressComplete: true, validationGranularity: "OTHER" },
                    address: { formattedAddress: "Conway, SC, USA" } }
        }.to_json)

        expect(validator.call(address).message).to include("specific building")
      end
    end

    it "flags an incomplete address and offers what Google did find" do
      with_key do
        stub_google(status: 200, body: {
          result: { verdict: { addressComplete: false, validationGranularity: "ROUTE" },
                    address: { formattedAddress: "Front St, Conway, SC, USA",
                               missingComponentTypes: [ "street_number" ] } }
        }.to_json)

        result = validator.call(address)

        expect(result).to be_suspect
        expect(result).to be_suggestion
        expect(result.message).to include("street_number")
      end
    end

    it "flags parts of the address it could not place" do
      with_key do
        stub_google(status: 200, body: {
          result: { verdict: { addressComplete: false, validationGranularity: "OTHER" },
                    address: { unresolvedTokens: [ "Nowhereville" ] } }
        }.to_json)

        expect(validator.call(address).message).to include("Nowhereville")
      end
    end
  end

  # The operator's requirement: a validation problem must never cost an
  # application. Every one of these lets the applicant straight through.
  describe "when the service is unusable" do
    it "skips when the daily quota is exhausted" do
      with_key do
        stub_google(status: 429, body: '{"error":{"message":"Quota exceeded"}}')

        expect(validator.call(address)).to be_skipped
      end
    end

    it "skips when the key is rejected" do
      with_key do
        stub_google(status: 403, body: '{"error":{"message":"API key not valid"}}')

        expect(validator.call(address)).to be_skipped
      end
    end

    it "skips when the connection times out" do
      with_key do
        allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout)

        expect(validator.call(address)).to be_skipped
      end
    end

    it "skips when the network is unreachable" do
      with_key do
        allow(Net::HTTP).to receive(:start).and_raise(SocketError, "getaddrinfo failed")

        expect(validator.call(address)).to be_skipped
      end
    end

    it "skips when Google returns something that is not JSON" do
      with_key do
        stub_google(status: 200, body: "<html>502 Bad Gateway</html>")

        expect(validator.call(address)).to be_skipped
      end
    end
  end

  it "skips a blank address rather than asking Google about nothing" do
    with_key do
      expect(Net::HTTP).not_to receive(:start)
      expect(validator.call("")).to be_skipped
      expect(validator.call(nil)).to be_skipped
    end
  end
end
