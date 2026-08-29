# frozen_string_literal: true

# Two changes to the wholesale application form, both from the operator.
#
# A separate shipping address, because a licensed retailer's registered business
# address is often not where stock is delivered. Optional: most applicants ship
# to the same place, and asking twice for the same address is friction.
#
# And the three "tell us about your business" questions stop being mandatory.
# They are useful colour for the operator when deciding, but an application is
# judged on the license, and blocking submission on "How did you hear about us?"
# loses real applicants.
class AddShippingAddressAndRelaxOptionalFieldsToApplications < ActiveRecord::Migration[8.0]
  def up
    add_column :nsb_wholesale_applications, :shipping_address, :text

    change_column_null :nsb_wholesale_applications, :sells, true
    change_column_null :nsb_wholesale_applications, :interested_in, true
    change_column_null :nsb_wholesale_applications, :heard_about_us, true
  end

  def down
    # Existing rows may now hold NULLs, so backfill before restoring the
    # constraint or the migration fails on real data.
    execute <<~SQL
      UPDATE nsb_wholesale_applications
         SET sells = COALESCE(sells, ''),
             interested_in = COALESCE(interested_in, ''),
             heard_about_us = COALESCE(heard_about_us, '')
    SQL

    change_column_null :nsb_wholesale_applications, :sells, false
    change_column_null :nsb_wholesale_applications, :interested_in, false
    change_column_null :nsb_wholesale_applications, :heard_about_us, false

    remove_column :nsb_wholesale_applications, :shipping_address
  end
end
