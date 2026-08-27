# frozen_string_literal: true

module Nsb
  # Closes the parts of the storefront that only make sense for a customer.
  #
  # The catalog itself stays open -- a prospect deciding whether to apply should
  # be able to see what we sell -- but pricing, the cart, checkout and order
  # history all require an account. Prices are hidden in the views
  # (ApplicationHelper#show_wholesale_prices?); this is the other half, stopping
  # someone from reaching the same numbers through the cart.
  #
  # Applied to adding to the cart and to checkout, and deliberately NOT to the
  # cart or order pages:
  #
  #   An anonymous cart is necessarily empty, because adding to it is gated.
  #
  #   Orders are reachable by signed token (/orders/:id/token/:token), which is
  #   the link in a customer's own confirmation email. Gating that would break
  #   order confirmations for the people they were sent to.
  #
  # Included per controller rather than applied in StoreController and skipped,
  # so that adding a new public page cannot accidentally inherit the gate, and
  # adding a new customer-only page fails open-nowhere: it simply is not gated
  # until someone includes this, which a request spec catches.
  module RequiresWholesaleAccount
    extend ActiveSupport::Concern

    included do
      before_action :require_wholesale_account
    end

    private

    def require_wholesale_account
      return if spree_current_user.present?

      # Remembered so the customer lands where they were going after signing in,
      # rather than on the catalog root wondering what happened.
      store_location if respond_to?(:store_location, true)
      redirect_to welcome_path
    end
  end
end
