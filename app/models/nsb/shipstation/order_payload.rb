# frozen_string_literal: true

module Nsb
  module Shipstation
    # Maps a Spree::Order onto ShipStation V1's Order object.
    #
    # Pure translation, no HTTP: that makes it testable without touching the
    # network, which matters because a wrong field here means an order that
    # ships to the wrong address rather than an error anyone notices.
    class OrderPayload
      # ShipStation truncates silently past this, so do it deliberately.
      MAX_ORDER_NUMBER = 50

      def initialize(order, config: Nsb::Shipstation::Configuration.new)
        @order = order
        @config = config
      end

      def to_h
        {
          # orderKey makes the push idempotent: ShipStation updates the matching
          # order rather than creating a duplicate. Without it, a retry after a
          # timeout would put the same order in the operator's queue twice.
          orderKey: order.number,
          orderNumber: order.number.to_s.first(MAX_ORDER_NUMBER),
          orderDate: (order.completed_at || Time.current).utc.iso8601,
          # Blank for a "Check (Net 14)" order (Nsb::CheckTerms), which ships
          # before it is paid. A card order is captured by Square before we get
          # here, so it is paid by completion.
          paymentDate: (order.completed_at&.utc&.iso8601 if order.paid?),
          # awaiting_shipment is what puts it in the operator's work queue --
          # for unpaid check orders too, since Net 14 means ship now, pay later.
          orderStatus: "awaiting_shipment",
          customerUsername: order.email,
          customerEmail: order.email,
          billTo: address(order.bill_address),
          shipTo: address(order.ship_address || order.bill_address),
          items: items,
          # What has actually been received: the full total for a card order,
          # zero for a check order still awaiting its check.
          amountPaid: money(order.payment_total),
          taxAmount: money(order.additional_tax_total),
          shippingAmount: money(order.ship_total),
          customerNotes: order.special_instructions.presence,
          # Surfaces the requested carrier in ShipStation without forcing it:
          # the operator still rate-shops, but sees what the customer picked.
          internalNotes: shipping_note,
          advancedOptions: advanced_options
        }.compact
      end

      private

      attr_reader :order, :config

      # Files the order under a specific ShipStation store. Omitted entirely
      # when unset, which lands it in Manual Orders -- workable, but mixed in
      # with hand-keyed orders.
      def advanced_options
        return nil if config.store_id.blank?

        { storeId: config.store_id }
      end

      def address(addr)
        return nil if addr.nil?

        {
          name: addr.name,
          company: addr.company.presence,
          street1: addr.address1,
          street2: addr.address2.presence,
          city: addr.city,
          state: addr.state&.abbr || addr.state_name,
          postalCode: addr.zipcode,
          country: addr.country&.iso,
          phone: addr.phone.presence
        }.compact
      end

      def items
        order.line_items.map do |line_item|
          variant = line_item.variant
          {
            lineItemKey: line_item.id.to_s,
            sku: variant.sku.presence,
            name: variant.product.name,
            quantity: line_item.quantity,
            unitPrice: money(line_item.price),
            imageUrl: nil
          }.compact
        end
      end

      def shipping_note
        names = order.shipments.filter_map { |s| s.selected_shipping_rate&.name }.uniq
        return nil if names.empty?

        "Customer selected: #{names.join(', ')}"
      end

      # ShipStation wants plain numbers, not BigDecimal or Money.
      def money(value)
        value.to_f.round(2)
      end
    end
  end
end
