# frozen_string_literal: true

require 'solidus_starter_frontend_spec_helper'

RSpec.describe Nsb::OrderFrequencyRanking do
  subject(:ranking) { described_class.new(scope: Spree::Product.all) }

  let(:fixture) do
    {
      source_file: 'orders_test.xlsx',
      total_orders: 100,
      total_line_items: 250,
      first_order_date: '2021-10-28',
      last_order_date: '2026-08-04',
      products: [
        # Leads on units, trails on dollars -- the two metrics must disagree so
        # the ordering tests are meaningful.
        { rank: 1, sku: 'BULK-SKU', name: 'Cheap and popular', orders: 50, units: 600.0,
          revenue: 600.0, customers: 9, first_ordered: '2021-11-16', last_ordered: '2026-07-31' },
        { rank: 2, sku: 'PRICEY-SKU', name: 'Dear and rare', orders: 30, units: 100.0,
          revenue: 3000.0, customers: 4, first_ordered: '2022-01-01', last_ordered: '2026-01-01' },
        { rank: 3, sku: 'GONE-SKU', name: 'Discontinued thing', orders: 20, units: 200.0,
          revenue: 400.0, customers: 4, first_ordered: '2022-01-01', last_ordered: '2023-01-01' },
        { rank: 4, sku: '', name: 'Blank Sku Product', orders: 10, units: 100.0,
          revenue: 1000.0, customers: 2, first_ordered: '2022-01-01', last_ordered: '2025-04-17' }
      ]
    }
  end

  # Held in a let so the Tempfile object stays referenced for the whole example.
  # Letting it fall out of scope lets the finalizer delete the file mid-test.
  let(:data_file) do
    file = Tempfile.new([ 'ranking', '.json' ])
    file.write(fixture.to_json)
    file.flush
    file
  end

  before { stub_const("#{described_class}::DATA_PATH", Pathname.new(data_file.path)) }

  let!(:bulk) { create(:product, name: 'Cheap and popular', sku: 'BULK-SKU') }
  let!(:pricey) { create(:product, name: 'Dear and rare', sku: 'PRICEY-SKU') }
  # Its SKU is blank in the export, so only the name can link it to the catalog.
  let!(:blank_sku_product) { create(:product, name: 'Blank Sku Product', sku: 'REAL-SKU') }
  let!(:never_ordered) { create(:product, name: 'Brand new item', sku: 'NEW-SKU') }

  describe '#entries' do
    it 'ranks by units sold by default' do
      expect(ranking.entries.map { |entry| entry.product.name })
        .to eq([ 'Cheap and popular', 'Dear and rare', 'Blank Sku Product' ])
    end

    it 'ranks by dollar sales when asked' do
      by_sales = described_class.new(scope: Spree::Product.all, metric: :sales)

      expect(by_sales.entries.map { |entry| entry.product.name })
        .to eq([ 'Dear and rare', 'Blank Sku Product', 'Cheap and popular' ])
    end

    it 'drops export rows with no product left in the catalog' do
      expect(ranking.entries.map { |entry| entry.product.name }).not_to include('Discontinued thing')
    end

    it 'excludes catalog products with no order history' do
      expect(ranking.entries.map { |entry| entry.product }).not_to include(never_ordered)
    end

    it 'renumbers ranks so the displayed list has no gaps' do
      expect(ranking.entries.map(&:rank)).to eq([ 1, 2, 3 ])
    end

    it 'falls back to matching on product name when the export has no SKU' do
      expect(ranking.entries.map(&:product)).to include(blank_sku_product)
    end
  end

  describe '#share' do
    # Units across the whole export, discontinued products included: 1000.
    it 'is the product share of total units on the default metric' do
      expect(ranking.entries.first.share).to eq(0.6)
    end

    # Revenue across the whole export: 5000.
    it 'is the product share of total sales on the sales metric' do
      by_sales = described_class.new(scope: Spree::Product.all, metric: :sales)

      expect(by_sales.entries.first.share).to eq(0.6)
    end

    it 'counts discontinued products in the denominator' do
      # 'Discontinued thing' holds 200 of the 1000 units, so the three surviving
      # products can only add up to 80%.
      expect(ranking.entries.sum(&:share)).to be_within(0.0001).of(0.8)
    end
  end

  describe '.metric_for' do
    it 'accepts the supported metrics' do
      expect(described_class.metric_for('sales')).to eq(:sales)
      expect(described_class.metric_for(:units)).to eq(:units)
    end

    it 'falls back to units for anything else' do
      expect(described_class.metric_for(nil)).to eq(:units)
      expect(described_class.metric_for('orders; DROP TABLE')).to eq(:units)
    end
  end

  describe '#max_share' do
    it 'is the leader share, for scaling the bars' do
      expect(ranking.max_share).to eq(ranking.entries.first.share)
    end
  end

  describe 'metadata' do
    it 'reads the date range from the export' do
      expect(ranking.first_order_date).to eq(Date.new(2021, 10, 28))
      expect(ranking.last_order_date).to eq(Date.new(2026, 8, 4))
    end

    it 'labels the selected metric' do
      expect(ranking.metric_label).to eq('Units sold')
      expect(ranking.share_suffix).to eq('of units sold')
    end
  end
end
