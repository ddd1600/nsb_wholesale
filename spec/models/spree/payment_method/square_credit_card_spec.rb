# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# Integration-level: the gateway specs prove the adapter classifies Square's
# answers correctly. These prove the WIRING -- that Solidus's payment state
# machine only reaches "completed" when Square actually confirmed the money
# moved. A green gateway spec over broken wiring is exactly the failure mode
# CLAUDE.md warns about, so this is asserted end to end through Spree::Payment.
RSpec.describe Spree::PaymentMethod::SquareCreditCard do
  let(:payment_method) { described_class.create!(name: "Square", auto_capture: true) }
  let(:order) { create(:order_with_line_items, state: "payment") }
  let(:credit_card) do
    create(:credit_card, gateway_payment_profile_id: "cnon:card-nonce-ok", last_digits: "1111", brand: "visa")
  end
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, source: credit_card, amount: 25.00)
  end

  let(:gateway) { instance_double(Nsb::Square::Gateway) }

  # Stub at construction rather than on one payment_method instance: reloading a
  # payment re-loads its payment_method association, which would otherwise hand
  # back an un-stubbed object and call the real Square client.
  before { allow(Nsb::Square::Gateway).to receive(:new).and_return(gateway) }

  def ok_response(id = "sq-pay-1")
    ActiveMerchant::Billing::Response.new(true, "Payment captured", { "payment_id" => id }, authorization: id)
  end

  def declined_response
    ActiveMerchant::Billing::Response.new(false, "Card declined by the issuing bank.", {}, authorization: nil)
  end

  describe "when Square confirms the charge" do
    it "completes the payment and records Square's payment id" do
      allow(gateway).to receive(:purchase).and_return(ok_response)

      payment.purchase!

      expect(payment.reload).to be_completed
      expect(payment.response_code).to eq("sq-pay-1")
    end
  end

  describe "when the card is declined" do
    before { allow(gateway).to receive(:purchase).and_return(declined_response) }

    it "leaves the payment failed, never completed" do
      expect { payment.purchase! }.to raise_error(Spree::Core::GatewayError)

      expect(payment.reload).to be_failed
      expect(payment).not_to be_completed
    end

    it "leaves the order unpaid" do
      expect { payment.purchase! }.to raise_error(Spree::Core::GatewayError)

      order.reload.recalculate
      expect(order.payment_state).not_to eq("paid")
    end

    it "surfaces the issuer's reason to the customer" do
      expect { payment.purchase! }
        .to raise_error(Spree::Core::GatewayError, /declined by the issuing bank/)
    end
  end

  describe "when the connection to Square fails mid-charge" do
    before do
      allow(gateway).to receive(:purchase)
        .and_raise(ActiveMerchant::ConnectionError.new("timeout", nil))
    end

    # The dangerous case: the charge may have succeeded at Square. Marking the
    # order paid would be guessing with the customer's money; so would marking
    # it failed and letting them retry blindly. Solidus raises and leaves the
    # payment un-completed, which is the only honest outcome.
    it "does not complete the payment" do
      expect { payment.purchase! }.to raise_error(Spree::Core::GatewayError)

      expect(payment.reload).not_to be_completed
    end

    it "leaves the order unpaid" do
      expect { payment.purchase! }.to raise_error(Spree::Core::GatewayError)

      order.reload.recalculate
      expect(order.payment_state).not_to eq("paid")
    end
  end

  describe "refunds" do
    it "sends a partial refund to the gateway against Square's payment id" do
      allow(gateway).to receive(:purchase).and_return(ok_response)
      payment.purchase!

      allow(gateway).to receive(:credit).and_return(
        ActiveMerchant::Billing::Response.new(true, "Refund completed", {}, authorization: "sq-ref-1")
      )
      # transaction_id must be nil for perform! to actually call the gateway --
      # Solidus treats a present transaction_id as "already refunded".
      refund = build(:refund, payment: payment.reload, amount: 10.00, transaction_id: nil)
      refund.perform!

      expect(gateway).to have_received(:credit).with(1000, "sq-pay-1", hash_including(originator: refund))
      expect(refund.transaction_id).to eq("sq-ref-1")
    end
  end

  describe "source handling" do
    it "does not offer a saved card for reuse, since Square tokens are single-use" do
      expect(payment_method.reusable_sources(order)).to eq([])
    end

    it "treats a source with no browser token as unusable" do
      expect(payment_method.supports?(create(:credit_card, gateway_payment_profile_id: nil))).to be(false)
    end

    it "cannot persist a card number or CVV" do
      # Spree::CreditCard exposes virtual number=/verification_value= accessors,
      # but there are no such database columns -- nothing can be written to disk.
      # Our flow never sets them either: the browser tokenises with Square's Web
      # Payments SDK and posts only gateway_payment_profile_id.
      expect(Spree::CreditCard.column_names).not_to include("number", "verification_value")

      # The factory assigns a number in memory; what matters is that reading the
      # record back from the database yields nothing, because there is nowhere
      # for it to have been written.
      persisted = Spree::CreditCard.find(credit_card.id)
      expect(persisted.attributes.keys).not_to include("number", "verification_value")
      expect(persisted.number).to be_blank
      expect(persisted.verification_value).to be_blank
    end
  end
end
