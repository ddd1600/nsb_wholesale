# frozen_string_literal: true

module Nsb
  module Admin
    # "Place an order" in the admin menu: pick a customer, then shop as them.
    #
    # The operator found no obvious way in. The only entry point was a small
    # "Place order" button on each row of the Users list, while the Orders
    # page's stock "New Order" button led to Solidus's back-office order form
    # instead -- a different flow that skips the storefront checkout. This page
    # is the one front door; the actual switch is still
    # Nsb::Admin::ImpersonationsController.
    class PlaceOrdersController < Spree::Admin::BaseController
      MAX_RESULTS = 25

      def index
        @query = params[:q].to_s.strip
        @customers = @query.present? ? search(@query) : []
      end

      private

      # Matches on email, or on the company or contact name of any saved
      # address -- the B2BWave import put each business name in the address.
      def search(query)
        pattern = "%#{Spree.user_class.sanitize_sql_like(query)}%"

        Spree.user_class
          .left_joins(:addresses)
          .where(
            "spree_users.email ILIKE :q OR spree_addresses.company ILIKE :q OR spree_addresses.name ILIKE :q",
            q: pattern
          )
          .distinct
          .order(:email)
          .limit(MAX_RESULTS)
          .reject { |user| user.has_spree_role?("admin") }
      end
    end
  end
end
