class AddB2bCustomerIdToSpreeUsers < ActiveRecord::Migration[8.0]
  # Idempotency key for the B2BWave customer migration, mirroring
  # spree_products.b2b_product_id.
  #
  # Email would work today (all 360 exported emails are unique and well-formed)
  # but it is user-editable: if someone corrects an address in admin, a re-import
  # would create a duplicate account. B2BWave's own customer_id cannot drift.
  def change
    add_column :spree_users, :b2b_customer_id, :integer, null: true
    add_index :spree_users, :b2b_customer_id, unique: true
  end
end
