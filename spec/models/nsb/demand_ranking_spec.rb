# frozen_string_literal: true

require 'solidus_starter_frontend_spec_helper'

RSpec.describe Nsb::DemandRanking do
  subject(:ranking) { described_class.new(scope: Spree::Product.available) }

  # Deliberately disagreeing datasets. Wholesale leads with the bulk item,
  # retail with the expensive one, and the two metrics disagree within each
  # channel -- so any test that passes by accident on one axis fails on another.
  let(:wholesale_data) do
    {
      channel: 'wholesale',
      first_order_date: '2021-10-28',
      last_order_date: '2026-08-04',
      total_units: 1000.0,
      total_sales: 5000.0,
      products: [
        { rank: 1, sku: 'BULK', name: 'Bulk item', units: 600.0, sales: 600.0 },
        { rank: 2, sku: 'DEAR', name: 'Dear item', units: 100.0, sales: 3000.0 },
        { rank: 3, sku: 'GONE', name: 'Discontinued item', units: 200.0, sales: 400.0 }
      ]
    }
  end

  let(:retail_data) do
    {
      channel: 'retail',
      first_sale_date: '2020-07-10',
      last_sale_date: '2026-08-24',
      total_units: 500.0,
      total_sales: 8000.0,
      products: [
        { rank: 1, sku: 'DEAR', name: 'Dear item', units: 250.0, sales: 6000.0 },
        { rank: 2, sku: 'BULK', name: 'Bulk item', units: 50.0, sales: 200.0 }
      ]
    }
  end

  let(:data_dir) { Pathname.new(Dir.mktmpdir) }

  before do
    data_dir.join('product_order_frequency.json').write(wholesale_data.to_json)
    data_dir.join('product_retail_frequency.json').write(retail_data.to_json)
    stub_const("#{described_class}::DATA_DIR", data_dir)
  end

  after { FileUtils.remove_entry(data_dir) }

  let!(:bulk) { create(:product, name: 'Bulk item', sku: 'BULK') }
  let!(:dear) { create(:product, name: 'Dear item', sku: 'DEAR') }
  let!(:untouched) { create(:product, name: 'Never sold', sku: 'NEW') }

  def names_for(channel:, metric:)
    described_class.new(scope: Spree::Product.available, channel: channel, metric: metric)
                   .entries.map { |entry| entry.product.name }
  end

  describe 'channels' do
    it 'ranks wholesale on its own figures' do
      expect(names_for(channel: :wholesale, metric: :units)).to eq([ 'Bulk item', 'Dear item' ])
    end

    it 'ranks retail on its own figures, which disagree with wholesale' do
      expect(names_for(channel: :retail, metric: :units)).to eq([ 'Dear item', 'Bulk item' ])
    end

    it 'defaults to wholesale' do
      expect(ranking.channel).to eq(:wholesale)
    end

    it 'never mixes the two: a share is of one channel only' do
      wholesale = described_class.new(scope: Spree::Product.available, channel: :wholesale, metric: :units)
      retail = described_class.new(scope: Spree::Product.available, channel: :retail, metric: :units)

      # 600/1000 wholesale, 50/500 retail. A combined figure would be 650/1500.
      expect(wholesale.entries.first.share).to eq(0.6)
      expect(retail.entries.last.share).to eq(0.1)
    end
  end

  describe 'metrics' do
    it 'ranks by units by default' do
      expect(ranking.metric).to eq(:units)
    end

    it 'reorders on dollar sales within wholesale' do
      expect(names_for(channel: :wholesale, metric: :sales)).to eq([ 'Dear item', 'Bulk item' ])
    end

    it 'reorders on dollar sales within retail' do
      expect(names_for(channel: :retail, metric: :sales)).to eq([ 'Dear item', 'Bulk item' ])
    end
  end

  describe 'shares' do
    it 'divides by the export total, not by the products that matched' do
      # 'Discontinued item' holds 200 of wholesale's 1000 units, so the two
      # surviving products can only account for 70%.
      expect(ranking.entries.sum(&:share)).to be_within(0.0001).of(0.7)
    end

    it 'uses the sales total on the sales metric' do
      by_sales = described_class.new(scope: Spree::Product.available, channel: :wholesale, metric: :sales)

      expect(by_sales.entries.first.share).to eq(0.6)
    end
  end

  describe 'what is excluded' do
    it 'drops export rows with no product left in the catalog' do
      expect(names_for(channel: :wholesale, metric: :units)).not_to include('Discontinued item')
    end

    it 'drops catalog products with no history on the selected channel' do
      expect(names_for(channel: :wholesale, metric: :units)).not_to include('Never sold')
    end

    it 'drops discontinued products, because the scope is Spree::Product.available' do
      bulk.update!(discontinue_on: 1.day.ago)

      expect(names_for(channel: :wholesale, metric: :units)).to eq([ 'Dear item' ])
    end

    it 'renumbers ranks so the displayed list has no gaps' do
      expect(ranking.entries.map(&:rank)).to eq([ 1, 2 ])
    end
  end

  # The regression that put the best-selling product in the catalog on nobody's
  # screen. Pack sizes that arrived from B2BWave as separate products were folded
  # into one product with a Pack Size variant, which moved the SKUs the order
  # history knows off the master and onto the variants. The index only read
  # master SKUs, so all three folded products vanished from every ranking -- and
  # nothing failed, the list was just quietly shorter.
  describe 'products sold as variants' do
    # Its own dataset, so the totals here cannot disturb the share arithmetic
    # the other examples assert on.
    let(:wholesale_data) do
      {
        channel: 'wholesale',
        first_order_date: '2021-10-28',
        last_order_date: '2026-08-04',
        total_units: 1000.0,
        total_sales: 1000.0,
        products: [
          { rank: 1, sku: 'GUMMY-30', name: 'Gummies 30ct', units: 600.0, sales: 600.0 },
          { rank: 2, sku: 'GUMMY-10', name: 'Gummies 10ct', units: 100.0, sales: 100.0 }
        ]
      }
    end

    # One product, two pack sizes. The SKUs the order history knows are on the
    # variants; the master carries a new SKU that appears in no export.
    let!(:gummies) do
      product = create(:product, name: 'Gummies', sku: 'GUMMY')
      size = Spree::OptionType.create!(name: 'pack_size', presentation: 'Pack Size')
      product.option_types << size
      %w[GUMMY-30 GUMMY-10].each_with_index do |sku, index|
        value = size.option_values.create!(name: "v#{index}", presentation: "#{sku}")
        product.variants.create!(sku: sku, option_values: [ value ])
      end
      product
    end

    it 'finds a product by a SKU that lives on a variant, not the master' do
      expect(names_for(channel: :wholesale, metric: :units)).to include('Gummies')
    end

    it 'adds up the export rows that now share one product' do
      entry = described_class.new(scope: Spree::Product.available, channel: :wholesale, metric: :units)
        .entries.find { |candidate| candidate.product == gummies }

      expect(entry.units).to eq(700.0)
      expect(entry.share).to eq(0.7)
    end

    it 'counts a folded product once, not once per pack size' do
      entries = described_class.new(scope: Spree::Product.available, channel: :wholesale, metric: :units).entries

      expect(entries.map(&:product).count(gummies)).to eq(1)
    end
  end

  describe 'parameter coercion' do
    it 'accepts the supported values' do
      expect(described_class.channel_for('retail')).to eq(:retail)
      expect(described_class.metric_for('sales')).to eq(:sales)
    end

    it 'falls back for anything else' do
      expect(described_class.channel_for('nonsense')).to eq(:wholesale)
      expect(described_class.metric_for(nil)).to eq(:units)
      expect(described_class.channel_for('retail; DROP TABLE')).to eq(:wholesale)
    end
  end

  describe 'labels and dates' do
    it 'reads each channel its own date range' do
      retail = described_class.new(scope: Spree::Product.available, channel: :retail)

      expect(ranking.first_date).to eq(Date.new(2021, 10, 28))
      expect(retail.first_date).to eq(Date.new(2020, 7, 10))
    end

    it 'names the channel and the metric' do
      expect(ranking.channel_label).to eq('Wholesale')
      expect(ranking.metric_label).to eq('Units sold')
      expect(ranking.share_suffix).to eq('of units sold')
    end
  end
end
