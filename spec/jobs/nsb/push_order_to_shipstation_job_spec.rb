# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# The point of these examples is the CLAUDE.md rule: an order must complete even
# if ShipStation is unreachable. Fulfilment is downstream; the order is the
# source of truth. Most of what follows asserts on failure, not success.
RSpec.describe Nsb::PushOrderToShipstationJob do
  let(:order) { create(:completed_order_with_totals) }
  let(:client) { instance_double(Nsb::Shipstation::Client) }
  let(:config) { instance_double(Nsb::Shipstation::Configuration, enabled?: true, store_id: nil) }

  before do
    allow(Nsb::Shipstation::Configuration).to receive(:new).and_return(config)
    allow(Nsb::Shipstation::Client).to receive(:new).and_return(client)
  end

  describe "a successful push" do
    before { allow(client).to receive(:create_order).and_return("orderId" => 987) }

    it "records the ShipStation order id on the order" do
      described_class.perform_now(order)

      status = order.reload.admin_metadata["shipstation"]
      expect(status["state"]).to eq("pushed")
      expect(status["shipstation_order_id"]).to eq(987)
    end
  end

  describe "when ShipStation is unreachable" do
    before do
      allow(client).to receive(:create_order)
        .and_raise(Nsb::Shipstation::Client::RetryableError, "Timed out talking to ShipStation")
    end

    # retry_on catches the error and schedules another attempt, so perform_now
    # returns rather than raising. That IS the desired behaviour: a ShipStation
    # outage must never surface as an exception anywhere near the order.
    it "does not raise, so nothing upstream can be disturbed" do
      expect { described_class.perform_now(order) }.not_to raise_error
    end

    it "leaves the order complete and paid" do
      described_class.perform_now(order)

      expect(order.reload).to be_completed
      expect(order.payment_state).not_to eq("failed")
    end

    it "records the failure where the operator can see it" do
      described_class.perform_now(order)

      status = order.reload.admin_metadata["shipstation"]
      expect(status["state"]).to eq("retrying")
      expect(status["error"]).to match(/Timed out/)
    end

    it "schedules a retry rather than giving up" do
      expect { described_class.perform_now(order) }
        .to have_enqueued_job(described_class)
    end
  end

  describe "when ShipStation rejects the order permanently" do
    before do
      allow(client).to receive(:create_order)
        .and_raise(Nsb::Shipstation::Client::PermanentError, "Invalid shipTo address")
    end

    it "does not retry forever -- it is discarded and recorded" do
      # discard_on means the job stops; the operator sees why rather than the
      # reason being buried under four more identical attempts.
      perform_enqueued_jobs do
        expect { described_class.perform_later(order) }.not_to raise_error
      end

      expect(order.reload.admin_metadata.dig("shipstation", "state")).to eq("failed")
    end

    it "still leaves the order complete" do
      perform_enqueued_jobs { described_class.perform_later(order) }

      expect(order.reload).to be_completed
    end
  end

  describe "when ShipStation is not configured" do
    let(:config) { instance_double(Nsb::Shipstation::Configuration, enabled?: false, store_id: nil) }

    it "skips quietly rather than failing, so orders still work without credentials" do
      expect { described_class.perform_now(order) }.not_to raise_error
      expect(order.reload.admin_metadata.dig("shipstation", "state")).to eq("skipped")
    end

    it "never calls ShipStation" do
      allow(client).to receive(:create_order)
      described_class.perform_now(order)

      expect(client).not_to have_received(:create_order)
    end
  end
end
