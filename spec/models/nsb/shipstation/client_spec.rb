# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# The classification of errors is the whole job of this class: retryable vs
# permanent decides whether the operator gets a recoverable blip or a message
# telling them something is actually wrong.
RSpec.describe Nsb::Shipstation::Client do
  let(:config) do
    instance_double(Nsb::Shipstation::Configuration,
      credentials!: %w[key secret],
      base_url: "https://ssapi.shipstation.com")
  end

  subject(:client) { described_class.new(config: config) }

  def stub_response(code, body = "{}")
    response = instance_double(Net::HTTPResponse, code: code.to_s, body: body)
    allow(Net::HTTP).to receive(:start).and_return(response)
    response
  end

  it "returns the parsed body on success" do
    stub_response(200, { orderId: 42 }.to_json)

    expect(client.create_order(orderKey: "R1")).to eq("orderId" => 42)
  end

  describe "retryable failures" do
    it "treats a timeout as retryable, since the push may yet succeed" do
      allow(Net::HTTP).to receive(:start).and_raise(Net::ReadTimeout)

      expect { client.create_order({}) }.to raise_error(described_class::RetryableError, /Timed out/)
    end

    it "treats an unreachable host as retryable" do
      allow(Net::HTTP).to receive(:start).and_raise(SocketError, "getaddrinfo failed")

      expect { client.create_order({}) }.to raise_error(described_class::RetryableError, /Could not reach/)
    end

    it "treats a 429 rate limit as retryable" do
      stub_response(429)

      expect { client.create_order({}) }.to raise_error(described_class::RetryableError, /rate limit/)
    end

    it "treats a 5xx as retryable" do
      stub_response(503)

      expect { client.create_order({}) }.to raise_error(described_class::RetryableError, /server error/)
    end
  end

  describe "permanent failures" do
    it "treats a 400 as permanent and surfaces ShipStation's reason" do
      stub_response(400, { Message: "Invalid shipTo address" }.to_json)

      expect { client.create_order({}) }
        .to raise_error(described_class::PermanentError, /Invalid shipTo address/)
    end

    it "treats bad credentials as permanent, since retrying cannot fix them" do
      stub_response(401, { Message: "Unauthorized" }.to_json)

      expect { client.create_order({}) }.to raise_error(described_class::PermanentError)
    end

    it "falls back to the raw body when the error is not JSON" do
      stub_response(400, "<html>Bad Request</html>")

      expect { client.create_order({}) }.to raise_error(described_class::PermanentError, /Bad Request/)
    end
  end

  it "raises MissingCredentials rather than calling out with a nil key" do
    allow(config).to receive(:credentials!)
      .and_raise(Nsb::Shipstation::Configuration::MissingCredentials, "missing SHIPSTATION_API_KEY")

    expect { client.create_order({}) }
      .to raise_error(Nsb::Shipstation::Configuration::MissingCredentials)
  end
end
