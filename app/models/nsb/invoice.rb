# frozen_string_literal: true

module Nsb
  # Everything an invoice shows for one completed order, in one place, so the
  # confirmation email (app/views/spree/order_mailer/confirm_email.*) and the
  # PDF (Nsb::InvoicePdf) cannot disagree.
  #
  # One row per line item. Solidus already keeps one line item per variant,
  # so each variety of a product is its own row.
  #
  # Totals are Solidus's own, unrecomputed: item_total + ship_total +
  # promo_total (negative; includes free shipping) + tax = total.
  class Invoice
    Row = Struct.new(:product, :variety, :sku, :quantity, :unit_price, :amount, keyword_init: true)
    Total = Struct.new(:label, :amount, :grand, keyword_init: true)

    NET_TERMS_DAYS = 14

    attr_reader :order, :store

    def initialize(order)
      @order = order
      @store = order.store || Spree::Store.default
    end

    def number = order.number
    def date = (order.completed_at || Time.current).to_date
    def bill_address = order.bill_address
    def ship_address = order.ship_address || order.bill_address

    def customer_name
      bill_address&.company.presence ||
        order.user&.admin_metadata&.dig("b2bwave", "company_name").presence ||
        bill_address&.name
    end

    def rows
      order.line_items.sort_by(&:id).map do |item|
        Row.new(
          product: item.variant.product.name,
          variety: item.variant.options_text.presence,
          sku: item.variant.sku.presence,
          quantity: item.quantity,
          unit_price: money(item.price),
          amount: money(item.amount)
        )
      end
    end

    def totals
      list = [ Total.new(label: "Subtotal", amount: money(order.item_total)) ]
      list << Total.new(label: "Shipping#{shipping_method_suffix}", amount: money(order.ship_total))
      list << Total.new(label: "Discounts", amount: money(order.promo_total)) unless order.promo_total.zero?
      list << Total.new(label: "Tax", amount: money(order.additional_tax_total)) unless order.additional_tax_total.zero?
      list << Total.new(label: "Total", amount: money(order.total), grand: true)
      list
    end

    # "Paid — Credit Card", or for Check (Net 14) the date the check is due.
    def payment_summary
      payment = order.payments.valid.last
      return "Balance due" unless payment

      method_name = payment.payment_method.name
      if order.paid?
        "Paid — #{method_name}"
      elsif payment.payment_method.is_a?(Spree::PaymentMethod::Check)
        "#{method_name} — due #{(date + NET_TERMS_DAYS).to_fs(:long)}"
      else
        "Balance due — #{method_name}"
      end
    end

    def logo_path
      Rails.root.join("app/assets/images/brand/nsb_logo_horizontal.png")
    end

    def business_name = "New South Botanicals"
    def phone = store.nsb_contact_phone
    def email = store.nsb_contact_email
    def notice = store.nsb_support_notice
    def mailing_address_lines = store.nsb_mailing_address.to_s.lines.map(&:strip).compact_blank

    def address_lines(address)
      return [] unless address

      [
        address.company,
        address.name,
        address.address1,
        address.address2,
        [ address.city, [ address.state&.abbr || address.state_name, address.zipcode ].compact_blank.join(" ") ].compact_blank.join(", "),
        address.phone
      ].compact_blank
    end

    private

    def shipping_method_suffix
      name = order.shipments.filter_map { |s| s.shipping_method&.name }.uniq.join(", ")
      name.present? ? " (#{name})" : ""
    end

    def money(amount)
      Spree::Money.new(amount, currency: order.currency).to_s
    end
  end
end
