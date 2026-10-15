# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

RSpec.describe "Saved cards", type: :request do
  let(:payment_method) { Spree::PaymentMethod::SquareCreditCard.create!(name: "Square", auto_capture: true) }
  let(:user) { create(:user, square_customer_id: "SQ-CUST-1") }
  let(:service) { instance_double(Nsb::Square::CardsOnFile) }

  def saved_card_for(owner, last_digits: "4242")
    card = create(:credit_card, payment_method: payment_method, user: owner, last_digits: last_digits,
                                gateway_payment_profile_id: "ccof:#{last_digits}",
                                gateway_customer_profile_id: owner.square_customer_id || "SQ-OTHER")
    owner.wallet.add(card)
  end

  before do
    allow(Nsb::Square::CardsOnFile).to receive(:new).and_return(service)
    sign_in user
  end

  describe "My Account" do
    it "lists saved cards, but not spent single-use tokens" do
      saved_card_for(user, last_digits: "4242")
      token_card = create(:credit_card, payment_method: payment_method, user: user, last_digits: "9999",
                                        gateway_payment_profile_id: "cnon:spent")
      user.wallet.add(token_card)

      get account_path

      expect(response.body).to include("ending 4242")
      expect(response.body).not_to include("ending 9999")
    end
  end

  describe "removing a card" do
    let!(:wallet_source) { saved_card_for(user) }

    it "disables it at Square, then removes it from the wallet" do
      allow(service).to receive(:disable).and_return(true)

      delete account_saved_card_path(wallet_source)

      expect(service).to have_received(:disable).with(wallet_source.payment_source)
      expect(Spree::WalletPaymentSource.where(user: user).to_a).to be_empty
      expect(response).to redirect_to(account_path)
    end

    it "keeps the card when Square does not confirm" do
      allow(service).to receive(:disable).and_return(false)

      delete account_saved_card_path(wallet_source)

      expect(Spree::WalletPaymentSource.where(user: user).to_a).to eq([wallet_source])
      expect(flash[:error]).to be_present
    end

    it "keeps the card when Square is unreachable" do
      allow(service).to receive(:disable).and_raise(Square::Errors::TimeoutError)

      delete account_saved_card_path(wallet_source)

      expect(Spree::WalletPaymentSource.where(user: user).to_a).to eq([wallet_source])
      expect(flash[:error]).to be_present
    end

    it "cannot touch another customer's card" do
      other = create(:user, square_customer_id: "SQ-CUST-2")
      their_source = saved_card_for(other)
      allow(service).to receive(:disable)

      delete account_saved_card_path(their_source)

      expect(response).to have_http_status(:not_found)
      expect(service).not_to have_received(:disable)
      expect(Spree::WalletPaymentSource.where(user: other).to_a).to eq([their_source])
    end
  end
end

RSpec.describe "Checkout card parameters", type: :request do
  # The browser must be able to ask for a card to be saved, but must NOT be able
  # to set the Square customer id that unlocks a saved card.
  it "lets a browser post the save box" do
    expect(Spree::PermittedAttributes.source_attributes).to include(:nsb_save_requested)
  end

  it "does not let a browser post a Square customer id" do
    expect(Spree::PermittedAttributes.source_attributes).not_to include(:gateway_customer_profile_id)
    expect(Spree::PermittedAttributes.checkout_payment_attributes.to_s).not_to include("gateway_customer_profile_id")
  end
end

RSpec.describe "Checkout payment step with saved cards", type: :request do
  let(:user) { create(:user, square_customer_id: "SQ-CUST-1") }
  let!(:payment_method) { Spree::PaymentMethod::SquareCreditCard.create!(name: "Square", auto_capture: true) }

  around do |example|
    ClimateControl.modify(SQUARE_APPLICATION_ID: "sandbox-app", SQUARE_LOCATION_ID: "LOC1") { example.run }
  end

  before do
    order = Spree::TestingSupport::OrderWalkthrough.up_to(:delivery)
    order.update!(user: user)
    order.next! # -> payment

    saved = create(:credit_card, payment_method: payment_method, user: user, last_digits: "4242",
                                 gateway_payment_profile_id: "ccof:1", gateway_customer_profile_id: "SQ-CUST-1")
    spent = create(:credit_card, payment_method: payment_method, user: user, last_digits: "9999",
                                 gateway_payment_profile_id: "cnon:spent")
    user.wallet.add(saved)
    user.wallet.add(spent)

    sign_in user
  end

  it "offers the saved card but not a spent single-use token" do
    get checkout_state_path("payment")

    expect(response.body).to include("ending 4242")
    expect(response.body).not_to include("ending 9999")
  end

  it "shows the Save this card box, unticked" do
    get checkout_state_path("payment")

    box = Nokogiri::HTML(response.body).at_css("input[type=checkbox][name='payment_source[#{payment_method.id}][nsb_save_requested]']")
    expect(box).to be_present
    expect(box["checked"]).to be_nil
  end
end

RSpec.describe "Admin charging a saved card", type: :request do
  let(:customer) { create(:user, square_customer_id: "SQ-CUST-1") }
  let(:order) { create(:completed_order_with_totals, user: customer) }
  let!(:payment_method) { Spree::PaymentMethod::SquareCreditCard.create!(name: "Square", auto_capture: true) }
  let!(:saved_card) do
    card = create(:credit_card, payment_method: payment_method, user: customer, last_digits: "4242",
                                gateway_payment_profile_id: "ccof:1", gateway_customer_profile_id: "SQ-CUST-1")
    customer.wallet.add(card)
    card
  end
  let(:gateway) { instance_double(Nsb::Square::Gateway) }

  before do
    allow(Nsb::Square::Gateway).to receive(:new).and_return(gateway)
    sign_in create(:admin_user)
  end

  it "lists the customer's saved card on the New Payment form" do
    get spree.new_admin_order_payment_path(order)

    expect(response.body).to include("Charge a saved card")
    expect(response.body).to include("ending 4242")
  end

  it "charges the chosen saved card through Square" do
    allow(gateway).to receive(:purchase).and_return(
      ActiveMerchant::Billing::Response.new(true, "Payment captured", {}, authorization: "sq-pay-9")
    )

    post spree.admin_order_payments_path(order),
      params: { payment: { payment_method_id: payment_method.id, amount: "12.00" }, card: saved_card.id }

    expect(gateway).to have_received(:purchase).with(1200, saved_card, anything)
    payment = order.payments.reload.find_by(response_code: "sq-pay-9")
    expect(payment).to be_completed
  end

  it "leaves the payment unpaid when Square declines the saved card" do
    allow(gateway).to receive(:purchase).and_return(
      ActiveMerchant::Billing::Response.new(false, "Your card was declined.", {})
    )

    post spree.admin_order_payments_path(order),
      params: { payment: { payment_method_id: payment_method.id, amount: "12.00" }, card: saved_card.id }

    payment = order.payments.reload.where(source: saved_card).last
    expect(payment).to be_failed
  end
end
