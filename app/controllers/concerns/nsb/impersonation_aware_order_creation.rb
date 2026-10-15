# frozen_string_literal: true

module Nsb
  # Solidus stamps a new order's created_by with spree_current_user (see
  # Spree::Core::ControllerHelpers::Order#current_order). While an admin is
  # impersonating a customer for a phone-in order, spree_current_user IS the
  # customer -- correct for who the order belongs to, but it would make a
  # staff-placed order indistinguishable from a self-service one in the admin
  # order view. Only created_by is redirected to the real admin; user,
  # addresses and wallet all stay pointed at the customer.
  #
  # Prepended onto StoreController (in solidus_decorators.rb), where
  # Spree::Core::ControllerHelpers::Order actually gets included -- see the
  # comment there -- matching how this app's other Solidus overrides are
  # applied.
  module ImpersonationAwareOrderCreation
    private

    def new_order_params
      params = super
      params[:created_by] = true_spree_user if impersonating_spree_user?
      params
    end
  end
end
