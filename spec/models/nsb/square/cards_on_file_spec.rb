# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# Square is stubbed here, so these prove what we ASK Square to do and what we
# record afterwards -- not that Square accepts it. The sandbox check in
# docs/SAVED_CARDS.md covers that.
RSpec.describe Nsb::Square::CardsOnFile do
  subject(:service) { described_class.new(config: config) }

  let(:cards_api) { instance_double("Square::Cards::Client") }
  let(:customers_api) { instance_double("Square::Customers::Client") }
  let(:square_client) { instance_double("Square::Client", cards: cards_api, customers: customers_api) }
  let(:config) { instance_double(Nsb::Square::Configuration, client: square_client) }

  let(:payment_method) { Spree::PaymentMethod::SquareCreditCard.create!(name: "Square", auto_capture: true) }
  let(:user) { create(:user) }
  let(:order) { create(:order_with_line_items, user: user) }
  let(:credit_card) do
    create(:credit_card, payment_method: payment_method, user: user, name: "Pat Buyer",
                         gateway_payment_profile_id: "cnon:spent-token", last_digits: "1111",
                         nsb_save_requested: true)
  end
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, source: credit_card,
                     amount: 25, state: "completed", response_code: "sq-pay-1")
  end

  def square_card(id: "ccof:card-1")
    double("Square::Types::Card", id: id, last_4: "1111", exp_month: 12, exp_year: 2030)
  end

  describe "#save_from_payment" do
    before do
      allow(customers_api).to receive(:create)
        .and_return(double(customer: double(id: "SQ-CUST-1")))
      allow(cards_api).to receive(:create).and_return(double(card: square_card))
    end

    it "asks Square to store the card from the completed payment, under the customer" do
      service.save_from_payment(payment)

      expect(cards_api).to have_received(:create).with(
        idempotency_key: "card-#{payment.number}",
        source_id: "sq-pay-1",
        card: hash_including(customer_id: "SQ-CUST-1")
      )
    end

    it "records Square's ids on the card, not any card data" do
      service.save_from_payment(payment)
      credit_card.reload

      expect(credit_card.gateway_customer_profile_id).to eq("SQ-CUST-1")
      expect(credit_card.gateway_payment_profile_id).to eq("ccof:card-1")
      expect(credit_card).to be_reusable
    end

    it "puts the card in the customer's wallet" do
      service.save_from_payment(payment)

      expect(user.wallet.wallet_payment_sources.map(&:payment_source)).to include(credit_card)
    end

    it "creates the Square customer once and remembers it" do
      service.save_from_payment(payment)

      expect(user.reload.square_customer_id).to eq("SQ-CUST-1")
      expect(customers_api).to have_received(:create).once
    end

    it "reuses an existing Square customer" do
      user.update_column(:square_customer_id, "SQ-EXISTING")

      service.save_from_payment(payment)

      expect(customers_api).not_to have_received(:create)
      expect(cards_api).to have_received(:create).with(hash_including(card: hash_including(customer_id: "SQ-EXISTING")))
    end

    it "leaves the card unsaved when Square refuses it" do
      allow(cards_api).to receive(:create).and_raise(Square::Errors::ClientError.new("{}", code: 400))

      expect { service.save_from_payment(payment) }.to raise_error(Square::Errors::ClientError)
      expect(credit_card.reload.gateway_customer_profile_id).to be_nil
      expect(credit_card).not_to be_reusable
    end
  end

  describe "#disable" do
    let(:credit_card) do
      create(:credit_card, payment_method: payment_method, user: user,
                           gateway_payment_profile_id: "ccof:card-1", gateway_customer_profile_id: "SQ-CUST-1")
    end

    it "is true when Square confirms the card is disabled" do
      allow(cards_api).to receive(:disable).with(card_id: "ccof:card-1")
        .and_return(double(card: double(enabled: false)))

      expect(service.disable(credit_card)).to be(true)
    end

    it "is false when Square does not confirm" do
      allow(cards_api).to receive(:disable).and_return(double(card: double(enabled: true)))

      expect(service.disable(credit_card)).to be(false)
    end

    it "is true when Square no longer knows the card" do
      allow(cards_api).to receive(:disable).and_raise(Square::Errors::NotFoundError.new("{}", code: 404))

      expect(service.disable(credit_card)).to be(true)
    end

    it "lets an outage propagate so the caller keeps the card" do
      allow(cards_api).to receive(:disable).and_raise(Square::Errors::TimeoutError)

      expect { service.disable(credit_card) }.to raise_error(Square::Errors::TimeoutError)
    end
  end
end
