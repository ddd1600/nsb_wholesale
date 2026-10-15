# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# The operator placing phone-in orders on behalf of a wholesale customer.
# spree_current_user swaps to the customer via the pretender gem (see
# ApplicationController); everything downstream -- cart, checkout, order
# association -- is stock Solidus behaviour reacting to that, not custom
# logic, so these specs focus on the part that IS custom: who can start/stop
# it, and who an order ends up belonging to.
RSpec.describe "Admin impersonation", type: :request do
  let!(:store) { create(:store) }
  let(:variant) { create(:variant) }
  let(:admin) { create(:admin_user) }
  let(:customer) { create(:user) }

  context "when signed in as an admin" do
    before { sign_in admin }

    it "starts placing an order for the chosen customer" do
      post admin_impersonations_path(user_id: customer.id)

      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(response.body).to include(customer.email)
    end

    it "refuses to impersonate another admin account" do
      other_admin = create(:admin_user)

      post admin_impersonations_path(user_id: other_admin.id)
      follow_redirect!

      expect(response.body).to include("place an order on behalf of an admin account")
    end

    it "associates a new order with the customer, and credits the admin as its creator" do
      post admin_impersonations_path(user_id: customer.id)

      expect do
        post cart_line_items_path, params: { variant_id: variant.id }
      end.to change(Spree::Order, :count).by(1)

      order = Spree::Order.last
      expect(order.user).to eq(customer)
      expect(order.created_by).to eq(admin)
    end

    it "locks /admin out for the duration, since Solidus authorizes off the impersonated customer" do
      post admin_impersonations_path(user_id: customer.id)

      get "/admin/wholesale_applications"

      expect(response).not_to have_http_status(:ok)
    end

    it "restores the admin's own access once stopped" do
      post admin_impersonations_path(user_id: customer.id)
      delete stop_impersonation_path

      expect(response).to redirect_to(root_path)

      get "/admin/wholesale_applications"
      expect(response).to have_http_status(:ok)
    end
  end

  context "when not an admin" do
    it "does not let a signed-out visitor start impersonating anyone" do
      post admin_impersonations_path(user_id: customer.id)

      expect(response).not_to have_http_status(:ok)
    end

    it "does not let an ordinary customer start impersonating anyone" do
      sign_in create(:user)

      post admin_impersonations_path(user_id: customer.id)

      expect(response).not_to have_http_status(:ok)
    end
  end
end
