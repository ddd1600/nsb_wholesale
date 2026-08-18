# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# CLAUDE.md: "an order should complete successfully even if ShipStation is
# briefly unreachable, with the fulfillment push retried or queued rather than
# blocking the customer."
#
# The job specs prove the job behaves. These prove the WIRING -- that finalizing
# an order only ever ENQUEUES, and that a ShipStation outage cannot reach the
# transaction that completes an order Square has already charged.
RSpec.describe "ShipStation isolation from checkout" do
  let(:order) { create(:order_ready_to_complete) }

  it "enqueues the push rather than calling ShipStation during checkout" do
    expect { order.complete! }.to have_enqueued_job(Nsb::PushOrderToShipstationJob)

    expect(order.reload).to be_completed
  end

  it "never opens an HTTP connection to ShipStation while completing the order" do
    client = instance_double(Nsb::Shipstation::Client)
    allow(Nsb::Shipstation::Client).to receive(:new).and_return(client)
    allow(client).to receive(:create_order)

    order.complete!

    # Enqueued, not performed: the customer's request does not wait on a third
    # party, and a slow ShipStation cannot slow checkout.
    expect(client).not_to have_received(:create_order)
  end

  it "completes the order even when ShipStation is completely down" do
    client = instance_double(Nsb::Shipstation::Client)
    allow(Nsb::Shipstation::Client).to receive(:new).and_return(client)
    allow(client).to receive(:create_order)
      .and_raise(Nsb::Shipstation::Client::RetryableError, "Could not reach ShipStation")
    allow(Nsb::Shipstation::Configuration).to receive(:new)
      .and_return(instance_double(Nsb::Shipstation::Configuration, enabled?: true, store_id: nil))

    # Force the job to run inline -- the worst case, as if the push happened
    # synchronously during checkout.
    perform_enqueued_jobs do
      expect { order.complete! }.not_to raise_error
    end

    expect(order.reload).to be_completed
    expect(order.payment_state).not_to eq("failed")
  end

  it "completes the order when ShipStation is not configured at all" do
    allow(Nsb::Shipstation::Configuration).to receive(:new)
      .and_return(instance_double(Nsb::Shipstation::Configuration, enabled?: false, store_id: nil))

    perform_enqueued_jobs do
      expect { order.complete! }.not_to raise_error
    end

    expect(order.reload).to be_completed
  end

  it "does not lose the order if enqueueing itself fails" do
    allow(Nsb::PushOrderToShipstationJob).to receive(:perform_later)
      .and_raise(StandardError, "queue backend exploded")

    expect { order.complete! }.not_to raise_error
    expect(order.reload).to be_completed
  end
end
