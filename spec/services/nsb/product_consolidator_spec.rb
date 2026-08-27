# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# B2BWave had no variant concept, so one product sold in two pack sizes arrived
# as two unrelated products. This folds them back together. The parts worth
# testing are the ones that fail silently: which variant the storefront
# preselects, and whether a second run duplicates anything.
RSpec.describe Nsb::ProductConsolidator do
  subject(:consolidator) { described_class.new(data_path: data_path, logger: Logger.new(IO::NULL)) }

  let(:data_path) { Rails.root.join("tmp", "product_variants_spec.json") }

  let(:config) do
    {
      "option_type" => { "name" => "pack_size", "presentation" => "Pack Size" },
      "consolidations" => [
        {
          "keep" => 100,
          "name" => "Test Gummies",
          "slug" => "test-gummies",
          "master_sku" => "TEST-Gummies",
          "variants" => [
            { "presentation" => "30ct", "sku" => "TEST-30", "price" => 30.0 },
            { "presentation" => "10ct", "sku" => "TEST-10", "price" => 12.5 }
          ],
          "supersedes" => [ { "b2b_product_id" => 101, "was_sku" => "TEST-10" } ]
        }
      ]
    }
  end

  before do
    File.write(data_path, JSON.pretty_generate(config))
    create(:product, b2b_product_id: 100, name: "Test Gummies (30ct)", sku: "TEST-30")
    create(:product, b2b_product_id: 101, name: "Test Gummies (10ct)", sku: "TEST-10")
  end

  after { FileUtils.rm_f(data_path) }

  def survivor = Spree::Product.find_by(b2b_product_id: 100)
  def superseded = Spree::Product.find_by(b2b_product_id: 101)

  it "renames the surviving product and gives it the new slug" do
    consolidator.call

    expect(survivor.name).to eq("Test Gummies")
    expect(survivor.slug).to eq("test-gummies")
  end

  it "creates one variant per pack size, with its own SKU and price" do
    result = consolidator.call

    variants = survivor.variants.order(:position)
    expect(result.variants_created).to eq(2)
    expect(variants.map(&:sku)).to eq(%w[TEST-30 TEST-10])
    expect(variants.map { |variant| variant.price.to_f }).to eq([ 30.0, 12.5 ])
  end

  # The operator asked for the larger pack to be the default everywhere. The
  # storefront preselects the first variant by position, so order is the feature.
  it "puts the pack size listed first at position 1, which is what the page preselects" do
    consolidator.call

    expect(survivor.variants.order(:position).first.options_text).to eq("Pack Size: 30ct")
  end

  it "moves the size-specific SKU off the master, which cannot hold it any more" do
    consolidator.call

    expect(survivor.master.sku).to eq("TEST-Gummies")
  end

  describe "the product that was folded in" do
    before { consolidator.call }

    it "is taken off the storefront rather than deleted, so history still resolves" do
      expect(superseded).to be_present
      expect(superseded.discontinue_on).to be_present
      expect(Spree::Product.available).not_to include(superseded)
    end

    # Solidus enforces SKU uniqueness across every variant that is not
    # soft-deleted, so leaving the SKU here would make the new variant invalid.
    it "gives up its SKU, because the new variant now claims it" do
      expect(superseded.master.sku).to eq("")
      expect(Spree::Variant.where(sku: "TEST-10").count).to eq(1)
    end
  end

  describe "running twice" do
    it "updates in place rather than duplicating variants" do
      consolidator.call
      second = consolidator.call

      expect(second.variants_created).to eq(0)
      expect(second.variants_updated).to eq(2)
      expect(survivor.variants.count).to eq(2)
    end

    it "does not accumulate option types on the product" do
      2.times { consolidator.call }

      expect(survivor.option_types.count).to eq(1)
    end
  end

  describe "when a price changes in the data file" do
    it "applies the new price to the existing variant" do
      consolidator.call
      config["consolidations"][0]["variants"][1]["price"] = 14.0
      File.write(data_path, JSON.pretty_generate(config))

      consolidator.call

      expect(survivor.variants.find_by(sku: "TEST-10").price.to_f).to eq(14.0)
    end
  end

  describe "when one consolidation is broken" do
    let(:config) do
      {
        "option_type" => { "name" => "pack_size", "presentation" => "Pack Size" },
        "consolidations" => [
          { "keep" => 999, "name" => "Missing", "master_sku" => "X", "variants" => [], "supersedes" => [] },
          {
            "keep" => 100,
            "name" => "Test Gummies",
            "master_sku" => "TEST-Gummies",
            "variants" => [ { "presentation" => "30ct", "sku" => "TEST-30", "price" => 30.0 } ],
            "supersedes" => []
          }
        ]
      }
    end

    # One bad row must not cost the whole run, and it must be reported rather
    # than swallowed -- the rake task exits non-zero on any failure.
    it "records the failure and still applies the good one" do
      result = consolidator.call

      expect(result.failures.size).to eq(1)
      expect(result.failures.first[:name]).to eq("Missing")
      expect(survivor.name).to eq("Test Gummies")
    end
  end
end
