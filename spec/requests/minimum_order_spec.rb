# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# The minimum order as a customer and the operator meet it: the cart's
# Checkout button, the checkout pages, the order-terms banner, and the two
# admin forms that set the amounts. The arithmetic is in
# spec/models/nsb/minimum_order_spec.rb.
RSpec.describe "Minimum order", type: :request do
  let!(:store) { create(:store, nsb_minimum_order_amount: 250) }
  let(:user) { create(:user) }

  context "as a signed-in customer" do
    before { sign_in user }

    let!(:order) { create(:order_with_line_items, user: user, store: store, line_items_price: 100) }

    it "keeps an order under the minimum on the cart page, saying why" do
      patch cart_path, params: { checkout: true }

      expect(response).to redirect_to(cart_path)
      expect(flash[:error]).to include("$250.00").and include("$150.00")
      expect(order.reload.state).to eq("cart")
    end

    it "tells the customer on the cart page how far short they are, and disables Checkout" do
      Nsb::PromotionSeeder.new.call

      get cart_path

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("#minimum-order-notice").text).to include("Add $150.00 more to reach your $250.00 minimum")
      expect(page.at_css("#free-shipping-notice").text).to include("Add $400.00 more for free shipping")
      expect(page.at_css("#checkout-link")["disabled"]).to be_present
    end

    it "sends a customer who goes straight to a checkout page back to the cart" do
      get checkout_state_path("address")

      expect(response).to redirect_to(cart_path)
      expect(flash[:error]).to include("$250.00")
    end

    it "lets an order at the minimum check out" do
      order.line_items.first.update!(price: 250)
      order.recalculate

      patch cart_path, params: { checkout: true }

      expect(order.reload.state).to eq("address")
    end

    it "shows the customer's own minimum in the banner when they have one" do
      user.update!(nsb_minimum_order_amount: 100)

      get root_path

      expect(response.body).to include("Minimum order $100")
    end

    it "cannot set its own minimum from the account page" do
      patch account_path, params: { user: { nsb_minimum_order_amount: 0 } }

      expect(response).to have_http_status(:redirect) # the update itself went through
      expect(user.reload.nsb_minimum_order_amount).to be_nil
    end
  end

  describe "the order-terms banner, signed out" do
    it "shows the site-wide minimum and the free-shipping threshold" do
      Nsb::PromotionSeeder.new.call

      get root_path
      follow_redirect! while response.redirect?

      expect(response.body).to include("Minimum order $250")
        .and include("Free shipping on orders over $500")
    end

    it "drops the free-shipping line when that promotion has expired" do
      Nsb::PromotionSeeder.new.call
      Spree::Promotion.find_by!(name: Nsb::PromotionSeeder::FREE_SHIPPING_NAME).update!(expires_at: 1.day.ago)

      get root_path
      follow_redirect! while response.redirect?

      expect(response.body).to include("Minimum order $250")
      expect(response.body).not_to include("Free shipping")
    end
  end

  context "as an admin" do
    before { sign_in create(:admin_user) }

    it "edits the site-wide minimum on the store form" do
      get spree.edit_admin_store_path(store)
      expect(response.body).to include("Minimum order amount (site-wide)")

      patch spree.admin_store_path(store), params: { store: { nsb_minimum_order_amount: "300" } }

      expect(store.reload.nsb_minimum_order_amount).to eq(300)
    end

    it "sets a customer's own minimum, and clears it back to the site-wide one" do
      get spree.edit_admin_user_path(user)
      expect(response.body).to include("Minimum order amount")

      patch spree.admin_user_path(user), params: { user: { nsb_minimum_order_amount: "75" } }
      expect(user.reload.nsb_minimum_order_amount).to eq(75)

      patch spree.admin_user_path(user), params: { user: { nsb_minimum_order_amount: "" } }
      expect(user.reload.nsb_minimum_order_amount).to be_nil
    end
  end
end
