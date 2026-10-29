# frozen_string_literal: true

# The business details printed on the order confirmation email and its PDF
# invoice (Nsb::Invoice), edited on Settings -> Stores -> edit.
#
# Also fills the store's stock "BCC Email" field, if empty, with the three
# addresses that get a copy of every order. That field is Solidus's own: its
# OrderMailer already BCCs it on every confirmation.
#
# Values are set here, once, rather than in Nsb::StoreConfigurator, which is
# re-run and would overwrite later admin edits.
class AddNsbInvoiceDetailsToStores < ActiveRecord::Migration[8.0]
  ORDER_COPY_RECIPIENTS = "ddd1600@gmail.com, david@newsouthbotanicals.com, pa@newsouthbotanicals.com"

  def up
    add_column :spree_stores, :nsb_contact_phone, :string
    add_column :spree_stores, :nsb_contact_email, :string
    add_column :spree_stores, :nsb_mailing_address, :text
    add_column :spree_stores, :nsb_support_notice, :text

    execute <<~SQL
      UPDATE spree_stores SET
        nsb_contact_phone = '843-222-2517',
        nsb_contact_email = 'david@newsouthbotanicals.com',
        nsb_mailing_address = E'506 8th Ave\\nAynor, SC 29511',
        nsb_support_notice = 'If you have any issues with your order, please call and leave a voicemail.'
    SQL
    execute <<~SQL
      UPDATE spree_stores SET bcc_email = '#{ORDER_COPY_RECIPIENTS}'
      WHERE bcc_email IS NULL OR bcc_email = ''
    SQL
  end

  def down
    remove_column :spree_stores, :nsb_support_notice
    remove_column :spree_stores, :nsb_mailing_address
    remove_column :spree_stores, :nsb_contact_email
    remove_column :spree_stores, :nsb_contact_phone
  end
end
