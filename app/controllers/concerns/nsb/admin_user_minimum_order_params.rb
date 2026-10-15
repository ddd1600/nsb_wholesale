# frozen_string_literal: true

module Nsb
  # Lets the admin user form save a customer's own minimum order amount.
  #
  # Added here, on the ADMIN users controller only, rather than to
  # Spree::PermittedAttributes.user_attributes: that list is also what the
  # storefront's account page and sign-up form permit, so putting it there would
  # let a customer set their own minimum to zero.
  #
  # A blank field is saved as NULL -- "use the store's site-wide minimum" -- not
  # as 0, which would mean "no minimum at all".
  #
  # Prepended onto Spree::Admin::UsersController in
  # config/initializers/solidus_decorators.rb.
  module AdminUserMinimumOrderParams
    private

    def user_params
      permitted = super
      if params[:user]&.key?(:nsb_minimum_order_amount)
        permitted[:nsb_minimum_order_amount] = params[:user][:nsb_minimum_order_amount].presence
      end
      permitted
    end
  end
end
