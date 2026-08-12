# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

RSpec.describe Nsb::ShippingMethodImporter do
  let(:data_file) { Pathname(Dir.mktmpdir) / "shipping_methods.json" }
  let!(:zone) { create(:zone, name: "North America") }

  def write(records) = data_file.write(JSON.generate(records))

  def record(overrides = {})
    { "name" => "UPS Ground Shipping", "sku" => "0010", "price" => 24.0 }.merge(overrides)
  end

  after { FileUtils.remove_entry(data_file.dirname) }

  subject(:importer) { described_class.new(data_file: data_file) }

  it "creates a flat-rate method at the price B2BWave charged" do
    write([record])

    result = importer.call

    expect(result.created).to eq(1)
    method = Spree::ShippingMethod.find_by(name: "UPS Ground Shipping")
    expect(method.code).to eq("0010")
    expect(method.calculator).to be_a(Spree::Calculator::Shipping::FlatRate)
    expect(method.calculator.preferred_amount).to eq(24.0)
  end

  it "attaches the North America zone so rates are actually offered" do
    write([record])

    importer.call

    expect(Spree::ShippingMethod.find_by(name: "UPS Ground Shipping").zones).to include(zone)
  end

  it "updates in place rather than duplicating when re-run" do
    write([record])
    importer.call

    write([record("price" => 26.5)])
    result = described_class.new(data_file: data_file).call

    expect(result.created).to eq(0)
    expect(Spree::ShippingMethod.where(name: "UPS Ground Shipping").count).to eq(1)
    expect(Spree::ShippingMethod.find_by(name: "UPS Ground Shipping").calculator.preferred_amount).to eq(26.5)
  end

  it "does not create products for shipping rows" do
    write([record])

    expect { importer.call }.not_to change { Spree::Product.count }
  end
end
