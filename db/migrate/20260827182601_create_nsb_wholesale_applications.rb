# frozen_string_literal: true

# Applications from businesses asking to become wholesale customers.
#
# Kept in its own table rather than as an unapproved Spree::User: an applicant is
# not a customer yet, and creating the account up front would put unvetted rows
# in the customer list, in the admin's user search, and in anything that counts
# customers. The Spree::User is created at approval, which is also the moment the
# claim email can be sent.
class CreateNsbWholesaleApplications < ActiveRecord::Migration[8.0]
  def change
    create_table :nsb_wholesale_applications do |t|
      # Who is asking, and how to reach them. Email carries the approval link, so
      # it is the one field the whole flow depends on being right.
      t.string :business_name, null: false
      t.string :contact_name, null: false
      t.string :email, null: false
      t.string :phone, null: false

      # Free text rather than street/city/state/zip: this is read by a person
      # deciding whether to approve, not used to calculate shipping. The real
      # address is collected by Solidus at the first order.
      t.text :address, null: false

      # Wholesale is licence-gated, so these are the fields the operator actually
      # vets on.
      t.string :retail_license_state, null: false
      t.string :retail_license_number, null: false

      t.text :sells, null: false
      t.text :interested_in, null: false
      t.text :heard_about_us, null: false

      # pending -> approved | declined. Declining is silent by design: it marks
      # the row reviewed so it leaves the pending list, and sends the applicant
      # nothing.
      t.string :status, null: false, default: "pending"
      t.datetime :reviewed_at

      # The account created when this was approved. Nullable because it only
      # exists after approval, and kept so the admin can get from an application
      # to the customer it became.
      t.references :user, foreign_key: { to_table: :spree_users }, null: true

      t.timestamps
    end

    # The pending list is the only query the admin runs often.
    add_index :nsb_wholesale_applications, [ :status, :created_at ]

    # Case-insensitive, because the whole point is to stop the same business
    # applying twice while the first application is still pending -- and people
    # do not type their address the same way twice.
    add_index :nsb_wholesale_applications, "lower(email)",
      name: "index_nsb_wholesale_applications_on_lower_email"
  end
end
