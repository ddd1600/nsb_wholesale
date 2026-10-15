# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

RSpec.describe Nsb::MinimumOrder do
  let(:store) { create(:store, nsb_minimum_order_amount: 250) }
  let(:user) { create(:user) }

  def order_totalling(amount, customer: user)
    create(:order_with_line_items, store: store, user: customer, line_items_price: amount)
  end

  describe "which minimum applies" do
    it "uses the store's site-wide minimum when the customer has none" do
      expect(order_totalling(10).nsb_minimum_order_amount).to eq(250)
    end

    it "uses the customer's own minimum when the admin has set one" do
      user.update!(nsb_minimum_order_amount: 100)

      expect(order_totalling(10).nsb_minimum_order_amount).to eq(100)
    end

    it "treats a customer minimum of 0 as no minimum, not as unset" do
      user.update!(nsb_minimum_order_amount: 0)

      expect(order_totalling(10).nsb_minimum_order_amount).to eq(0)
    end
  end

  describe "leaving the cart" do
    it "refuses to check out below the minimum and says by how much" do
      order = order_totalling(200)

      expect(order.next).to be(false)
      expect(order.reload.state).to eq("cart")
      expect(order.errors.full_messages.join).to include("$250.00").and include("$50.00")
    end

    it "allows an order of exactly the minimum" do
      order = order_totalling(250)

      expect(order.next).to be(true)
      expect(order.state).to eq("address")
    end

    it "lets a customer with a lower minimum through" do
      user.update!(nsb_minimum_order_amount: 100)

      expect(order_totalling(150).next).to be(true)
    end

    it "measures the subtotal before discounts, so $250 with NEWPORTAL still qualifies" do
      Nsb::PromotionSeeder.new.call
      order = order_totalling(250)
      order.coupon_code = "newportal"
      Spree::PromotionHandler::Coupon.new(order).apply

      expect(order.reload.promo_total).to eq(-50)
      expect(order.next).to be(true)
    end
  end

  describe "the backstop before confirm" do
    # Covers the customer who walks forward from /checkout/address without
    # ever leaving :cart through the state machine.
    it "will not reach confirm, so payment is never attempted, below the minimum" do
      order = create(:order_with_line_items, store: store, user: user, line_items_price: 300)
      order.update_columns(state: "payment")
      order.line_items.first.update!(price: 100)
      order.recalculate

      expect(order.next).to be(false)
      expect(order.reload.state).to eq("payment")
    end
  end
end
