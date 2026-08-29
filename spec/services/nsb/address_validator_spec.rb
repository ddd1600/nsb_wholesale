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
    it "confirms an address Google resolves completely" do
      with_key do
        stub_google(status: 200, body: {
          result: { verdict: { addressComplete: true },
                    address: { formattedAddress: "12 Front St, Conway, SC 29526, USA" } }
        }.to_json)

        result = validator.call(address)

        expect(result).to be_confirmed
        expect(result.formatted_address).to eq("12 Front St, Conway, SC 29526, USA")
      end
    end

    it "flags an incomplete address and offers what Google did find" do
      with_key do
        stub_google(status: 200, body: {
          result: { verdict: { addressComplete: false },
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
          result: { verdict: { addressComplete: false },
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
