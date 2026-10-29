# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# The admin's "Place an order" page (Nsb::Admin::PlaceOrdersController): the
# front door to the phone-in order flow. The switch into the customer's account
# itself is covered in spec/requests/admin_impersonation_spec.rb; the ordering
# and matching rules in spec/models/nsb/customer_directory_spec.rb.
RSpec.describe "Admin place an order", type: :request do
  let!(:store) { create(:store) }
  # Shaped like a B2BWave import: no address, business name in admin_metadata.
  let!(:customer) do
    create(:user, email: "linnrav@example.com", admin_metadata: {
      "b2bwave" => { "company_name" => "Back To Nature", "name" => "Lynn Ravare",
                     "latest_order_submitted_at" => "07/31/2026 11:13" }
    })
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

    it "lists customers without a search, with their last B2BWave order" do
      get admin_place_order_path

      expect(response.body).to include("Back To Nature")
      expect(response.body).to include("July 31, 2026")
      expect(response.body).to include("on B2BWave")
      expect(response.body).to include(admin_impersonations_path(user_id: customer.id))
    end

    it "filters loosely, so 'back 2 nature' finds Back To Nature" do
      create(:user, email: "other@example.com")

      get admin_place_order_path, params: { q: "back 2 nature" }

      expect(response.body).to include("Back To Nature")
      expect(response.body).not_to include("other@example.com")
    end

    it "pages through customers 25 at a time" do
      create_list(:user, 25)

      get admin_place_order_path
      expect(Nokogiri::HTML(response.body).css("table.index tbody tr").size).to eq(25)

      get admin_place_order_path, params: { page: 2 }
      expect(Nokogiri::HTML(response.body).css("table.index tbody tr").size).to eq(1)
    end
  end

  describe "the storefront's Admin button" do
    it "shows for an admin" do
      sign_in create(:admin_user)

      get root_path

      expect(Nokogiri::HTML(response.body).at_css("a[href='#{spree.admin_path}']")&.text).to eq("Admin")
    end

    it "is hidden from customers" do
      sign_in customer

      get root_path

      expect(Nokogiri::HTML(response.body).at_css("a[href='#{spree.admin_path}']")).to be_nil
    end
  end

  it "is closed to customers" do
    sign_in customer

    get admin_place_order_path

    expect(response.body).not_to include("Shop as this customer")
  end
end
