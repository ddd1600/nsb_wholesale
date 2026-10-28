# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# The admin's "Place an order" page (Nsb::Admin::PlaceOrdersController): the
# front door to the phone-in order flow. The switch into the customer's account
# itself is covered in spec/requests/admin_impersonation_spec.rb.
RSpec.describe "Admin place an order", type: :request do
  let!(:store) { create(:store) }
  let!(:customer) do
    create(:user, email: "buyer@backtonature.example").tap do |user|
      user.save_in_address_book(build(:address, company: "Back to Nature").attributes.except("id", "created_at", "updated_at"), true)
    end
  end

  context "as an admin" do
    before { sign_in create(:admin_user) }

    it "is linked from the admin menu and the Orders page" do
      get spree.admin_orders_path

      page = Nokogiri::HTML(response.body)

      expect(page.at_css("a[href='#{admin_place_order_path}'].icon_link").text).to include("Place an order")
      expect(page.at_css("#admin_new_order")["href"]).to eq(admin_place_order_path)
      expect(page.at_css("#admin_new_order").text).to eq("Place an order for a customer")
    end

    it "finds a customer by business name and offers to shop as them" do
      get admin_place_order_path, params: { q: "back to nat" }

      expect(response.body).to include("Back to Nature")
      expect(response.body).to include("Shop as this customer")
      expect(response.body).to include(admin_impersonations_path(user_id: customer.id))
    end

    it "finds a customer by email" do
      get admin_place_order_path, params: { q: "buyer@backtonature" }

      expect(response.body).to include(customer.email)
    end

    it "never lists admin accounts" do
      create(:admin_user, email: "boss@backtonature.example")

      get admin_place_order_path, params: { q: "backtonature" }

      expect(response.body).not_to include("boss@backtonature.example")
    end
  end

  it "is closed to customers" do
    sign_in customer

    get admin_place_order_path

    expect(response.body).not_to include("Shop as this customer")
  end
end
