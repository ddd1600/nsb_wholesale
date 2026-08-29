# frozen_string_literal: true

# What Google made of each address, kept with the application.
#
# The applicant can always submit an address we could not verify -- blocking
# would cost real retailers on rural routes and new builds. But the person
# approving the application should not have to take the address on trust: this
# is what tells them "we could not confirm this one" at the moment they decide.
class AddAddressVerdictsToApplications < ActiveRecord::Migration[8.0]
  def change
    add_column :nsb_wholesale_applications, :address_verdict, :string
    add_column :nsb_wholesale_applications, :shipping_address_verdict, :string
  end
end
