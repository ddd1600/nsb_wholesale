# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

RSpec.describe Nsb::PromotionSeeder do
  let!(:store) { create(:store) }
  let(:user) { create(:user) }

  before { described_class.new.call }

  def apply_code(order, code)
    order.coupon_code = code
    Spree::PromotionHandler::Coupon.new(order).apply
  end

  it "is safe to re-run and does not overwrite an admin's edits" do
    rule = Spree::Promotion.find_by!(name: described_class::FREE_SHIPPING_NAME).rules.first
    rule.update!(preferred_amount: 750)

    expect { described_class.new.call }.not_to change(Spree::Promotion, :count)
    expect(rule.reload.preferred_amount).to eq(750)
  end

  describe "NEWPORTAL" do
    it "takes 20% off the merchandise, whatever case it is typed in" do
      order = create(:order_with_line_items, user: user, store: store, line_items_price: 300)

      handler = apply_code(order, "NewPortal")

      expect(handler).to be_successful
      expect(order.reload.promo_total).to eq(-60)
    end

    it "can be used once per account" do
      first = create(:completed_order_with_promotion, user: user, store: store,
        promotion: Spree::Promotion.with_coupon_code("newportal"))
      expect(first).to be_completed

      second = create(:order_with_line_items, user: user, store: store, line_items_price: 300)
      handler = apply_code(second, "NEWPORTAL")

      expect(handler).not_to be_successful
      expect(second.reload.promo_total).to eq(0)
    end

    it "is still available to a different account" do
      create(:completed_order_with_promotion, user: user, store: store,
        promotion: Spree::Promotion.with_coupon_code("newportal"))

      other = create(:order_with_line_items, user: create(:user), store: store, line_items_price: 300)

      expect(apply_code(other, "newportal")).to be_successful
    end
  end

  describe "free shipping" do
    def order_at_delivery(subtotal)
      order = create(:order_with_line_items, user: user, store: store, line_items_price: subtotal,
        shipment_cost: 24)
      Spree::PromotionHandler::Cart.new(order).activate
      order.recalculate
      order
    end

    it "applies at exactly $500 (>=, not >)" do
      expect(order_at_delivery(500).shipments.sum(&:total_before_tax)).to eq(0)
    end

    it "does not apply below $500" do
      expect(order_at_delivery(499.99).shipments.sum(&:total_before_tax)).to eq(24)
    end
  end
end
