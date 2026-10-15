# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# The WIRING of saved cards, through Solidus's real order and payment models:
#
#   checkout with "Save this card" ticked -> Square charge confirmed -> order
#   complete -> job enqueued (never run inside checkout) -> card saved with
#   Square -> offered at the next checkout.
#
# Square itself is stubbed at the gateway / client boundary.
RSpec.describe "Saved cards flow" do
  let(:payment_method) { Spree::PaymentMethod::SquareCreditCard.create!(name: "Square", auto_capture: true) }
  let(:order) { create(:order_ready_to_complete) }
  let(:user) { order.user }
  let(:save_requested) { true }
  let(:credit_card) do
    create(:credit_card, payment_method: payment_method, user: user,
                         gateway_payment_profile_id: "cnon:browser-token", last_digits: "1111",
                         nsb_save_requested: save_requested)
  end

  let(:gateway) { instance_double(Nsb::Square::Gateway) }

  before do
    allow(Nsb::Square::Gateway).to receive(:new).and_return(gateway)
    order.payments.destroy_all
    create(:payment, order: order, payment_method: payment_method, source: credit_card,
                     amount: order.total, state: "checkout")
    order.reload
  end

  def charge_succeeds
    allow(gateway).to receive(:purchase).and_return(
      ActiveMerchant::Billing::Response.new(true, "Payment captured", {}, authorization: "sq-pay-1")
    )
  end

  context "when the customer ticked Save this card" do
    before { charge_succeeds }

    it "enqueues the save after checkout rather than calling Square during it" do
      expect { order.complete! }.to have_enqueued_job(Nsb::SaveCardOnFileJob)
      expect(order.reload).to be_completed
    end

    it "does not offer the spent browser token before Square has saved the card" do
      order.complete!

      next_order = create(:order, user: user)
      expect(payment_method.reusable_sources(next_order)).to be_empty
    end

    it "offers the card at the next checkout once the job has saved it" do
      order.complete!

      cards_api = double("cards", create: double(card: double(id: "ccof:card-1", last_4: "1111", exp_month: 12, exp_year: 2030)))
      customers_api = double("customers", create: double(customer: double(id: "SQ-CUST-1")))
      config = instance_double(Nsb::Square::Configuration,
        client: double(cards: cards_api, customers: customers_api))
      allow(Nsb::Square::Configuration).to receive(:new).and_return(config)

      Nsb::SaveCardOnFileJob.perform_now(order.payments.completed.first)

      next_order = create(:order, user: user)
      expect(payment_method.reusable_sources(next_order)).to eq([credit_card.reload])
    end
  end

  context "when the customer did not tick Save this card" do
    let(:save_requested) { false }

    before { charge_succeeds }

    it "never asks Square to save it" do
      expect { order.complete! }.not_to have_enqueued_job(Nsb::SaveCardOnFileJob)
    end
  end

  context "when the charge is declined" do
    before do
      allow(gateway).to receive(:purchase).and_return(
        ActiveMerchant::Billing::Response.new(false, "Your card was declined.", {})
      )
    end

    it "does not complete the order or save the card" do
      expect { order.complete! rescue nil }.not_to have_enqueued_job(Nsb::SaveCardOnFileJob)
      expect(order.reload).not_to be_completed
    end
  end
end

RSpec.describe Nsb::SaveCardOnFileJob do
  include ActiveJob::TestHelper

  # A real record: a retry re-enqueues the job, which serialises the payment.
  let(:payment) { create(:payment) }
  let(:service) { instance_double(Nsb::Square::CardsOnFile) }

  before do
    allow(described_class).to receive(:wanted?).and_return(true)
    allow(Nsb::Square::CardsOnFile).to receive(:new).and_return(service)
  end

  # Active Job checks handlers last-declared first, and ServerError is a
  # ResponseError subclass -- declared the wrong way round, a Square outage
  # would be discarded instead of retried.
  it "retries when Square has a server error" do
    allow(service).to receive(:save_from_payment).and_raise(Square::Errors::ServerError.new("boom", code: 500))

    expect { described_class.perform_now(payment) }.to have_enqueued_job(described_class)
  end

  it "retries when Square times out" do
    allow(service).to receive(:save_from_payment).and_raise(Square::Errors::TimeoutError)

    expect { described_class.perform_now(payment) }.to have_enqueued_job(described_class)
  end

  it "gives up, without raising, when Square refuses the card" do
    allow(service).to receive(:save_from_payment).and_raise(Square::Errors::ClientError.new("{}", code: 400))

    expect { described_class.perform_now(payment) }.not_to have_enqueued_job(described_class)
  end
end
