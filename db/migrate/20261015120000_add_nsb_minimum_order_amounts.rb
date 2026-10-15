# frozen_string_literal: true

# Minimum order value, enforced at checkout (Nsb::MinimumOrder).
#
# Two levels, both edited in the Solidus admin:
#   - spree_stores: the site-wide minimum (Settings -> Stores).
#   - spree_users:  a per-customer override (Users -> edit). NULL means "use the
#     site-wide minimum"; 0 means "this customer has no minimum".
#
# The store column defaults to 0 so that a store created anywhere else -- a test,
# a fresh database before seeding -- has no minimum, and only the real store is
# given the operator's $250 below. Setting it here rather than in
# Nsb::StoreConfigurator, because that task is re-run and would overwrite
# whatever the operator later sets in the admin.
class AddNsbMinimumOrderAmounts < ActiveRecord::Migration[8.0]
  def up
    add_column :spree_stores, :nsb_minimum_order_amount, :decimal,
      precision: 10, scale: 2, null: false, default: 0
    add_column :spree_users, :nsb_minimum_order_amount, :decimal,
      precision: 10, scale: 2

    execute "UPDATE spree_stores SET nsb_minimum_order_amount = 250"
  end

  def down
    remove_column :spree_users, :nsb_minimum_order_amount
    remove_column :spree_stores, :nsb_minimum_order_amount
  end
end
