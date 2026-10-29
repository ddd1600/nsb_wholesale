# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# The order confirmation email as an invoice (Nsb::Invoice, Nsb::InvoicePdf,
# Nsb::OrderConfirmationInvoice). Sent to the customer, BCC'd to staff
# through the store's "BCC Email" field.
RSpec.describe "Order confirmation invoice", type: :mailer do
  let!(:store) do
    create(:store,
      bcc_email: "ddd1600@gmail.com, david@newsouthbotanicals.com, pa@newsouthbotanicals.com",
      nsb_contact_phone: "843-222-2517",
      nsb_contact_email: "david@newsouthbotanicals.com",
      nsb_mailing_address: "506 8th Ave\nAynor, SC 29511",
      nsb_support_notice: "If you have any issues with your order, please call and leave a voicemail.")
  end
  let(:product) { create(:product, name: "Supreme Gummies") }
  let(:size) { create(:option_type, name: "pack-size", presentation: "Pack Size") }
  let(:small) { create(:variant, product: product, sku: "GUM-30", price: 20, option_values: [ create(:option_value, option_type: size, presentation: "30ct") ]) }
  let(:large) { create(:variant, product: product, sku: "GUM-60", price: 35, option_values: [ create(:option_value, option_type: size, presentation: "60ct") ]) }
  let(:order) do
    create(:completed_order_with_totals, store: store, line_items_count: 0).tap do |o|
      o.contents.add(small, 3)
      o.contents.add(large, 2)
      o.recalculate
    end
  end

  subject(:mail) { Spree::OrderMailer.confirm_email(order) }

  it "goes to the customer, with a copy to the three staff addresses" do
    expect(mail.to).to eq([ order.email ])
    expect(mail.bcc).to eq(%w[ddd1600@gmail.com david@newsouthbotanicals.com pa@newsouthbotanicals.com])
  end

  it "lists each variety on its own row with quantity, price and amount" do
    body = mail.html_part.decoded

    expect(body).to include("Supreme Gummies").and include("Pack Size: 30ct").and include("Pack Size: 60ct")
    expect(body).to include("GUM-30").and include("$60.00") # 3 x $20
    expect(body).to include("GUM-60").and include("$70.00") # 2 x $35
  end

  it "shows shipping and a total that includes it" do
    body = mail.text_part.decoded

    expect(body).to include("Subtotal: $130.00")
    expect(body).to match(/Shipping.*: \$#{format('%.2f', order.ship_total)}/)
    expect(body).to include("Total: #{order.display_total}")
    expect(order.total).to eq(order.item_total + order.ship_total + order.adjustment_total)
  end

  it "carries the business's phone, email, mailing address and voicemail notice" do
    body = mail.text_part.decoded

    expect(body).to include("843-222-2517", "david@newsouthbotanicals.com", "506 8th Ave", "Aynor, SC 29511")
    expect(body).to include("please call and leave a voicemail")
  end

  it "attaches a printable PDF invoice" do
    attachment = mail.attachments.first

    expect(attachment.filename).to eq("invoice-#{order.number}.pdf")
    expect(attachment.mime_type).to eq("application/pdf")
    expect(attachment.decoded).to start_with("%PDF")
  end

  it "shows a Check (Net 14) order's due date instead of calling it paid" do
    check = Nsb::CheckTerms.ensure_payment_method!
    order.payments.destroy_all
    create(:payment, order: order, payment_method: check, source: nil, amount: order.total, state: "checkout")
    order.update_columns(payment_state: "balance_due", completed_at: Time.zone.parse("2026-10-01 10:00"))

    expect(Nsb::Invoice.new(order.reload).payment_summary).to eq("Check (Net 14) — due October 15, 2026")
  end

  it "survives a product name the PDF font cannot draw" do
    product.update_column(:name, "Gummies ✓ 果")

    expect(mail.attachments.first.decoded).to start_with("%PDF")
  end
end

RSpec.describe "Invoice details on the admin store form", type: :request do
  let!(:store) { create(:store) }

  before { sign_in create(:admin_user) }

  it "edits the phone, contact email, mailing address and notice" do
    get spree.edit_admin_store_path(store)
    expect(response.body).to include("Invoice details")

    patch spree.admin_store_path(store), params: { store: {
      nsb_contact_phone: "843-555-0000", nsb_contact_email: "x@example.com",
      nsb_mailing_address: "1 Main St\nAynor, SC", nsb_support_notice: "Call us."
    } }

    store.reload
    expect(store.nsb_contact_phone).to eq("843-555-0000")
    expect(store.nsb_contact_email).to eq("x@example.com")
    expect(store.nsb_mailing_address).to eq("1 Main St\nAynor, SC")
    expect(store.nsb_support_notice).to eq("Call us.")
  end
end
