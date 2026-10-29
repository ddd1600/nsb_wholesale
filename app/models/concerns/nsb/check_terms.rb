# frozen_string_literal: true

module Nsb
  # "Check (Net 14)": pay by check within 14 days. Offered only when BOTH:
  #   - an admin is placing the order on the customer's behalf (the phone-in
  #     flow), set per request by CheckoutBaseController as
  #     #nsb_placed_by_admin; customers never choose it themselves, and
  #   - the customer has "Can pay by check" ticked (spree_users.nsb_pays_by_check,
  #     on the admin user form). Today that is Back to Nature.
  # Everyone checking out on their own, flagged or not, gets card only.
  #
  # Uses Solidus's own Spree::PaymentMethod::Check. Nothing is charged, and the
  # order is NOT marked paid: it completes with its payment left in "checkout"
  # and the order's payment state "balance due". The operator marks it paid by
  # clicking Capture on the order's Payments tab once the check arrives.
  #
  # Hidden from everyone else by narrowing Order#available_payment_methods,
  # which is both what the checkout page lists and what Solidus looks the
  # submitted payment_method_id up in -- so a forged id is refused, not just
  # hidden. The admin's own "New payment" form uses a separate list
  # (available_to_admin) and still offers Check, since the admin is trusted.
  #
  # Prepended onto Spree::Order in config/initializers/solidus_decorators.rb.
  module CheckTerms
    NAME = "Check (Net 14)"
    DESCRIPTION = "Pay by check within 14 days. Your order ships as normal; " \
                  "please mail the check with your order number on it."

    # Creates the payment method if there isn't one yet. Called from a
    # migration (so it reaches production on deploy) and from db/seeds.rb (a
    # fresh database loads the schema and skips migrations). Leaves an existing
    # one alone, so admin edits to it survive.
    def self.ensure_payment_method!
      Spree::PaymentMethod::Check.find_or_create_by!(name: NAME) do |method|
        method.description = DESCRIPTION
        method.active = true
        method.available_to_users = true
        method.available_to_admin = true
        # Must stay false. True would "purchase" on completion, and Solidus's
        # Check purchase is a simulated success -- the order would show paid
        # before any check exists.
        method.auto_capture = false
      end
    end

    # Not a column: who is acting is a fact about the request, not the order.
    # Defaults to false, so any code path that does not set it (the API, a
    # console, a job) gets card only.
    attr_accessor :nsb_placed_by_admin

    def nsb_check_terms_allowed?
      nsb_placed_by_admin == true && user&.nsb_pays_by_check? == true
    end

    def available_payment_methods
      methods = super
      return methods if nsb_check_terms_allowed?

      methods.where.not(type: Spree::PaymentMethod::Check.name)
    end
  end
end
