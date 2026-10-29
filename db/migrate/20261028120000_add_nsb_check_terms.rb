# frozen_string_literal: true

# "Check (Net 14)" for selected customers (Nsb::CheckTerms).
#
# Adds the per-customer switch, off for everyone, and creates the payment
# method so it reaches production on deploy rather than waiting on a rake task
# someone has to remember (see 20261015140000_create_order_terms_promotions).
# Which customers get it is set in the admin: Users -> the customer ->
# "Can pay by check (Net 14)".
class AddNsbCheckTerms < ActiveRecord::Migration[8.0]
  def up
    add_column :spree_users, :nsb_pays_by_check, :boolean, null: false, default: false

    Spree.user_class.reset_column_information
    Nsb::CheckTerms.ensure_payment_method!
  end

  def down
    # The payment method is left in place: completed orders may reference it.
    remove_column :spree_users, :nsb_pays_by_check
  end
end
