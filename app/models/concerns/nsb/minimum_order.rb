# frozen_string_literal: true

module Nsb
  # A minimum order value, checked when the customer leaves the cart and again
  # before the order can reach confirm (and so before any card is charged).
  #
  # Which minimum applies:
  #   1. the customer's own (spree_users.nsb_minimum_order_amount), if set --
  #      including 0, which means "no minimum for this customer";
  #   2. otherwise the store's site-wide minimum (spree_stores, default $250).
  # Both are edited in the Solidus admin; see the overrides under
  # app/overrides/spree/admin/.
  #
  # Measured against item_total: the merchandise subtotal BEFORE discounts and
  # shipping. So a $250 cart still qualifies with NEWPORTAL's 20% off. This is
  # the same figure Solidus's own ItemTotal promotion rule uses for the $500
  # free-shipping threshold, so the two cannot disagree about what "the order
  # total" means.
  #
  # Two checkpoints in the state machine:
  #   - from: :cart  -- the cart page's Checkout button. Stops the customer early
  #     with a clear message, before they type an address.
  #   - to: :confirm -- the backstop. The starter checkout lets a customer
  #     navigate straight to /checkout/address and walk forward without ever
  #     leaving :cart through the state machine. :complete is reachable only
  #     from :confirm, so nothing completes under the minimum.
  #
  # Deliberately NOT a `to: :complete` callback. Solidus charges the card in
  # its own before_transition to :complete (process_payments_before_complete),
  # and callbacks run in the order they were added -- one added here would run
  # AFTER the charge, refusing an order whose card had already been charged.
  # Entering :confirm comes before any payment is processed. CheckoutBaseController
  # also checks on every checkout page, which covers a cart edited while the
  # order sits at :confirm.
  #
  # Applies to orders placed from the Solidus admin too. To take a small phone
  # order, give that customer a lower minimum on their account first.
  #
  # Prepended onto Spree::Order in config/initializers/solidus_decorators.rb.
  module MinimumOrder
    def self.prepended(base)
      base.singleton_class.prepend(ReinstallOnNewStateMachine)
      install_callbacks(base)
    end

    # Adds the two checkpoints to the order's CURRENT state machine, once.
    #
    # Keyed on the machine object, not a plain "done" flag. Solidus throws the
    # machine away and builds a new one whenever the checkout flow is
    # redefined (Spree::Order.checkout_flow / insert_checkout_step), which
    # would otherwise silently drop the minimum. And to_prepare runs again on
    # every development reload without Spree::Order (a gem class) reloading,
    # so this must not stack duplicates either.
    def self.install_callbacks(order_class)
      machine = order_class.state_machine
      return if order_class.instance_variable_get(:@nsb_minimum_order_machine).equal?(machine)

      machine.before_transition from: :cart, do: :nsb_ensure_minimum_order
      machine.before_transition to: :confirm, do: :nsb_ensure_minimum_order
      order_class.instance_variable_set(:@nsb_minimum_order_machine, machine)
    end

    module ReinstallOnNewStateMachine
      def define_state_machine!
        super.tap { Nsb::MinimumOrder.install_callbacks(self) }
      end
    end

    def nsb_minimum_order_amount
      customer_minimum = user&.nsb_minimum_order_amount
      return customer_minimum unless customer_minimum.nil?

      store&.nsb_minimum_order_amount || BigDecimal("0")
    end

    def nsb_meets_minimum_order?
      item_total >= nsb_minimum_order_amount
    end

    # How much more the customer needs to add. Zero once they qualify.
    def nsb_amount_short_of_minimum
      [ nsb_minimum_order_amount - item_total, 0 ].max
    end

    def nsb_minimum_order_message
      I18n.t("nsb.minimum_order.not_met",
        minimum: Spree::Money.new(nsb_minimum_order_amount, currency: currency).to_s,
        short: Spree::Money.new(nsb_amount_short_of_minimum, currency: currency).to_s)
    end

    private

    # Returning false halts the transition; the message is what the storefront
    # shows in its flash.
    def nsb_ensure_minimum_order
      return true if nsb_meets_minimum_order?

      errors.add(:base, nsb_minimum_order_message)
      false
    end
  end
end
