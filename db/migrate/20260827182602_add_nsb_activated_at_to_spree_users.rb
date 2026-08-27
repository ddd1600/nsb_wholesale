# frozen_string_literal: true

# When a wholesale customer first set a password and became able to order.
#
# Exists to make the activation notification fire exactly once. Every migrated
# customer arrives with a random password they must replace, and the operator
# wants to know the moment each of the 360 accounts comes to life -- but a
# customer who later resets a forgotten password is not activating again, and an
# email saying they did would be wrong twice over.
#
# Nullable and never backfilled: the migrated accounts genuinely have not been
# activated yet, which is the whole point of the claim flow.
class AddNsbActivatedAtToSpreeUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :spree_users, :nsb_activated_at, :datetime
  end
end
