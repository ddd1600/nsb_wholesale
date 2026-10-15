# frozen_string_literal: true

# Saved cards, held by Square (card on file), never by us.
#
#   spree_users.square_customer_id      - the customer's Square customer profile.
#                                         A Square card on file must belong to one.
#   spree_credit_cards.nsb_save_requested - the customer ticked "Save this card"
#                                         at checkout. Nsb::SaveCardOnFileJob only
#                                         saves a card when this is true.
#
# Once saved, the Square card id lives in gateway_payment_profile_id and the
# Square customer id in gateway_customer_profile_id -- Solidus's conventional
# slots for a gateway-held card. See Nsb::Square::CardsOnFile.
class AddNsbSavedCards < ActiveRecord::Migration[8.0]
  def change
    add_column :spree_users, :square_customer_id, :string
    add_index :spree_users, :square_customer_id, unique: true

    add_column :spree_credit_cards, :nsb_save_requested, :boolean, null: false, default: false
  end
end
