# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

RSpec.describe Nsb::Shipstation::OrderPayload do
  let(:usa) { create(:country, iso: "US", name: "United States of America") }
  let!(:state) { create(:state, country: usa, name: "South Carolina", abbr: "SC") }
  let(:address) do
    create(:address, name: "Alex Buyer", company: "14 Carrot Whole Foods",
                     address1: "100 Main St", city: "Lexington", zipcode: "29072",
                     state: state, country: usa, phone: "8035551234")
  end
  let(:order) { create(:completed_order_with_totals, bill_address: address, ship_address: address) }

  subject(:payload) { described_class.new(order.reload).to_h }

  it "uses the Solidus order number as the idempotency key" do
    # ShipStation matches on orderKey, so a retry updates rather than putting a
    # duplicate in the operator's pick queue.
    expect(payload[:orderKey]).to eq(order.number)
    expect(payload[:orderNumber]).to eq(order.number)
  end

  it "marks the order awaiting shipment, since Square already took payment" do
    expect(payload[:orderStatus]).to eq("awaiting_shipment")
  end

  it "maps the shipping address into ShipStation's shape" do
    expect(payload[:shipTo]).to include(
      name: "Alex Buyer", company: "14 Carrot Whole Foods", street1: "100 Main St",
      city: "Lexington", state: "SC", postalCode: "29072", country: "US"
    )
  end

  it "sends line items with sku, quantity and price" do
    item = payload[:items].first
    expect(item).to include(:sku, :name, :quantity, :unitPrice)
    expect(item[:quantity]).to be_positive
  end

  it "sends money as plain rounded numbers, not Money or BigDecimal" do
    expect(payload[:amountPaid]).to be_a(Float)
    expect(payload[:shippingAmount]).to be_a(Float)
  end

  it "falls back to the billing address when there is no shipping address" do
    order.update_column(:ship_address_id, nil)

    expect(described_class.new(order.reload).to_h[:shipTo][:street1]).to eq("100 Main St")
  end

  it "omits blank optional fields rather than sending nulls" do
    expect(payload.values).not_to include(nil)
    expect(payload[:shipTo].values).not_to include(nil)
  end

  it "truncates an over-long order number instead of letting ShipStation do it silently" do
    allow(order).to receive(:number).and_return("R" * 80)

    expect(described_class.new(order).to_h[:orderNumber].length).to eq(50)
  end

  describe "which ShipStation store the order lands in" do
    it "targets the configured store, so orders do not sit in Manual Orders" do
      config = instance_double(Nsb::Shipstation::Configuration, store_id: 4242)

      built = described_class.new(order.reload, config: config).to_h

      expect(built[:advancedOptions]).to eq(storeId: 4242)
    end

    it "omits advancedOptions entirely when no store is configured" do
      config = instance_double(Nsb::Shipstation::Configuration, store_id: nil)

      built = described_class.new(order.reload, config: config).to_h

      # Sending a null storeId is not the same as omitting it; ShipStation
      # rejects unexpected nulls in advancedOptions.
      expect(built).not_to have_key(:advancedOptions)
    end
  end
end
