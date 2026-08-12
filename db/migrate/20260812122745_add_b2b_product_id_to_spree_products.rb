class AddB2bProductIdToSpreeProducts < ActiveRecord::Migration[8.0]
  # Stable idempotency key for the B2BWave catalog migration.
  #
  # SKU cannot serve as the key: one live product ("THC Free Green Apple
  # Gummies") ships with the placeholder SKU "-", and SKUs are editable in
  # admin, so keying on them would create duplicates on re-import.
  # b2b_product_id is B2BWave's own row id -- populated and unique for all 44
  # exported records -- so re-running the importer updates in place.
  #
  # Nullable on purpose: products created in Solidus after the migration have
  # no B2BWave counterpart.
  def change
    add_column :spree_products, :b2b_product_id, :integer, null: true
    add_index :spree_products, :b2b_product_id, unique: true
  end
end
