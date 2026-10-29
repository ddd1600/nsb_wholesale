# frozen_string_literal: true

# Solidus's models live inside the gem, so app-side behaviour is added by
# prepending modules onto them. to_prepare re-applies these on every reload in
# development; a plain initializer would attach to a stale class after the first
# code reload.
#
# Keep this list short and each module small -- see CLAUDE.md.
Rails.application.config.to_prepare do
  # Account claiming for customers migrated from B2BWave.
  Spree.user_class.prepend(Nsb::UserClaimable)

  # Free-text note on refunds, paired with the "Other" refund reason.
  Spree::Refund.prepend(Nsb::RefundNote)

  # Attributes a phone-in order's created_by to the admin who actually placed
  # it, not the customer being impersonated. Prepended onto StoreController
  # (app/controllers/store_controller.rb), not Spree::BaseController: that's
  # where Spree::Core::ControllerHelpers::Order (new_order_params) actually
  # gets included, and prepending any higher up the chain would be shadowed
  # by it.
  StoreController.prepend(Nsb::ImpersonationAwareOrderCreation)

  # Minimum order value: site-wide on the store, overridable per customer.
  Spree::Order.prepend(Nsb::MinimumOrder)
  Spree::Admin::UsersController.prepend(Nsb::AdminUserMinimumOrderParams)

  # "Check (Net 14)", offered only to customers flagged for it.
  Spree::Order.prepend(Nsb::CheckTerms)
  Spree::Admin::UsersController.prepend(Nsb::AdminUserCheckTermsParams)

  # Printable PDF invoice on the order confirmation email.
  Spree::OrderMailer.prepend(Nsb::OrderConfirmationInvoice)

  # Square cards count as saved only once Square holds them, not merely
  # because they carry a single-use browser token.
  Spree::CreditCard.prepend(Nsb::SquareSavedCard)
end
