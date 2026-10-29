# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# "Check (Net 14)" (Nsb::CheckTerms): offered only to customers flagged for it,
# refused for everyone else even when posted by hand, and never marks the order
# paid until the operator captures it.
RSpec.describe "Check (Net 14) payment", type: :request, with_signed_in_user: true do
  let!(:store) { create(:store, nsb_minimum_order_amount: 0) }
  let!(:card_method) { create(:credit_card_payment_method) }
  let!(:check_method) { Nsb::CheckTerms.ensure_payment_method! }
  let(:user) { order.user }
  let(:order) { create(:order_with_line_items, state: "payment", store: store) }

  let(:check_params) do
    { state: "payment", order: { payments_attributes: [ { payment_method_id: check_method.id.to_s } ] } }
  end

  context "for a customer without net terms" do
    it "is not listed on the payment page" do
      get checkout_state_path("payment")

      expect(response.body).not_to include("Check (Net 14)")
      expect(response.body).to include(card_method.name)
    end

    it "is refused when posted by hand, leaving the order without a payment" do
      patch update_checkout_path(check_params)

      expect(response.status).to eq(404)
      expect(order.reload.state).to eq("payment")
      expect(order.payments).to be_empty
    end
  end

  context "for a customer with net terms" do
    before { order.user.update!(nsb_pays_by_check: true) }

    it "is listed on the payment page" do
      get checkout_state_path("payment")

      expect(response.body).to include("Check (Net 14)")
    end

    it "completes the order unpaid, and only capture marks it paid" do
      patch update_checkout_path(check_params)
      expect(order.reload.state).to eq("confirm")

      patch update_checkout_path(state: "confirm")
      order.reload

      expect(order).to be_complete
      expect(order.payment_state).to eq("balance_due")
      expect(order.payment_total).to eq(0)
      expect(order.payments.last.state).to eq("checkout")

      # What the admin's Capture button does when the check arrives.
      order.payments.last.capture!
      order.reload

      expect(order.payment_state).to eq("paid")
      expect(order.payment_total).to eq(order.total)
    end
  end

  it "leaves the payment method set not to capture automatically" do
    expect(check_method.auto_capture).to be(false)
  end

  it "cannot be switched on by the customer from their account page" do
    patch account_path, params: { user: { nsb_pays_by_check: "1" } }

    expect(user.reload.nsb_pays_by_check).to be(false)
  end
end

RSpec.describe "Check (Net 14) admin switch", type: :request do
  let!(:store) { create(:store) }
  let(:customer) { create(:user) }

  before { sign_in create(:admin_user) }

  it "is ticked and unticked on the admin user form" do
    get spree.edit_admin_user_path(customer)
    expect(response.body).to include("Can pay by check (Net 14)")

    patch spree.admin_user_path(customer), params: { user: { nsb_pays_by_check: "1" } }
    expect(customer.reload.nsb_pays_by_check).to be(true)

    patch spree.admin_user_path(customer), params: { user: { nsb_pays_by_check: "0" } }
    expect(customer.reload.nsb_pays_by_check).to be(false)
  end
end
