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
    #
    # Lists every customer, most recent order first (Nsb::CustomerDirectory),
    # with an optional filter box.
    class PlaceOrdersController < Spree::Admin::BaseController
      PER_PAGE = 25

      def index
        @query = params[:q].to_s.strip
        @entries = Kaminari
          .paginate_array(Nsb::CustomerDirectory.new(query: @query).entries)
          .page(params[:page])
          .per(PER_PAGE)
      end
    end
  end
end
