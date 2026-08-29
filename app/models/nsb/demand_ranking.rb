# frozen_string_literal: true

module Nsb
  # Ranks the current Solidus catalog by historical demand.
  #
  # Two independent channels, never combined:
  #
  #   :wholesale  the legacy B2BWave portal's order export (361 orders,
  #               Oct 2021 - Aug 2026), aggregated by
  #               script/rank_products_by_orders.py.
  #   :retail     the Square item exports covering the company's own online and
  #               in-store sales (Jul 2020 - Aug 2026), aggregated by
  #               script/rank_retail_sales.py.
  #
  # Each channel has its own file, its own denominators and its own percentages.
  # A product's retail share says nothing about its wholesale share and the two
  # are never added together -- they are different customers buying at different
  # prices, and a combined number would mean nothing.
  #
  # Within a channel the ranking can be read by units sold or by dollar sales.
  #
  # Reading pre-aggregated files rather than querying is deliberate: both sources
  # are historical exports that do not change between deploys, and this store has
  # no Spree::Order history of its own yet.
  class DemandRanking
    DATA_DIR = Rails.root.join("db/import_data")

    CHANNELS = {
      wholesale: {
        file: "product_order_frequency.json",
        label: "Wholesale",
        from: "first_order_date",
        to: "last_order_date",
        blurb: "wholesale orders placed"
      },
      retail: {
        file: "product_retail_frequency.json",
        label: "Retail",
        from: "first_sale_date",
        to: "last_sale_date",
        blurb: "retail sales made"
      }
    }.freeze

    METRICS = {
      units: { field: "units", total: "total_units", label: "Units sold", share_suffix: "of units sold" },
      sales: { field: "sales", total: "total_sales", label: "Dollar sales", share_suffix: "of sales" }
    }.freeze

    DEFAULT_CHANNEL = :wholesale
    DEFAULT_METRIC = :units

    class << self
      # Coerce anything -- a query param, nil, junk -- to a supported value.
      def channel_for(value) = key_for(value, CHANNELS, DEFAULT_CHANNEL)
      def metric_for(value) = key_for(value, METRICS, DEFAULT_METRIC)

      private

      def key_for(value, allowed, fallback)
        key = value.to_s.downcase.to_sym
        allowed.key?(key) ? key : fallback
      end
    end

    # One catalog product plus its demand on the selected channel. `rank` is the
    # position within *this* list, not the raw export -- products that are no
    # longer in the catalog are dropped first, so raw ranks would have gaps.
    Entry = Struct.new(:product, :rank, :units, :sales, :share, keyword_init: true)

    attr_reader :channel, :metric

    def initialize(scope: Spree::Product.available, channel: DEFAULT_CHANNEL, metric: DEFAULT_METRIC)
      @scope = scope
      @channel = self.class.channel_for(channel)
      @metric = self.class.metric_for(metric)
    end

    def channel_label = CHANNELS.fetch(channel)[:label]
    def metric_label = METRICS.fetch(metric)[:label]

    # "of units sold" / "of sales" -- the tail of every percentage on the page.
    def share_suffix = METRICS.fetch(metric)[:share_suffix]

    # "wholesale orders placed" / "retail sales made"
    def blurb = CHANNELS.fetch(channel)[:blurb]

    # Ranked best-to-worst on the selected metric. Only products still in the
    # catalog appear, so anything discontinued drops out on its own -- the scope
    # defaults to Spree::Product.available, which filters discontinue_on.
    # Products with no history on this channel never appear either; there is
    # nothing to rank them by.
    def entries
      @entries ||= begin
        field = METRICS.fetch(metric)[:field]

        matched.sort_by { |_product, row| -row.fetch(field).to_f }.each_with_index.map do |(product, row), index|
          Entry.new(
            product: product,
            rank: index + 1,
            units: row["units"],
            sales: row["sales"],
            share: total.positive? ? row.fetch(field).to_f / total : 0.0
          )
        end
      end
    end

    # Scales the frequency bars: everything is measured against the leader rather
    # than against 100%, otherwise every bar below the top few is a sliver.
    def max_share = entries.first&.share || 0.0

    def first_date = Date.parse(data.fetch(CHANNELS.fetch(channel)[:from]))
    def last_date = Date.parse(data.fetch(CHANNELS.fetch(channel)[:to]))

    private

    attr_reader :scope

    # The denominator comes from the file, not from the products we managed to
    # match. Both exports count demand we can no longer sell -- discontinued
    # wholesale lines, retail-only items like vape carts and single taffies --
    # and dropping those from the denominator would inflate everything left.
    def total = data.fetch(METRICS.fetch(metric)[:total]).to_f

    # Export rows folded onto the catalog products they belong to.
    #
    # Several rows can land on one product, and their demand is added together
    # rather than one of them winning. That is the normal case now: pack sizes
    # that arrived from B2BWave as separate products are sold as variants of a
    # single product, so the two Delta 8 gummy rows are two sizes of one thing
    # the page sells. Showing one size's units under a product that sells both
    # would understate it.
    def matched
      @matched ||= begin
        index = catalog_index
        grouped = {}

        data.fetch("products").each do |row|
          product = index[row["sku"].to_s.strip.presence] || index[normalize(row["name"])]
          next if product.nil?

          (grouped[product] ||= []) << row
        end

        grouped.map { |product, rows| [ product, combine(rows) ] }
      end
    end

    def combine(rows)
      return rows.first if rows.one?

      {
        "units" => rows.sum { |row| row["units"].to_f },
        "sales" => rows.sum { |row| row["sales"].to_f }
      }
    end

    # One lookup from "whatever the export called it" to a catalog product.
    #
    # Keyed on EVERY variant's SKU, not just the master's. Pack sizes that used
    # to be separate products are now variants of one, so the SKUs the order
    # history knows -- E-D8Gummies10Ct and its siblings -- are variant SKUs, and
    # a master-only index silently dropped all three gummy products, the best
    # seller in the catalog among them. Names are indexed too, for the export
    # rows whose SKU was left blank.
    def catalog_index
      scope.to_a.each_with_object({}) do |product, index|
        index[normalize(product.name)] ||= product

        product.variants_including_master.each do |variant|
          key = variant.sku.to_s.strip.presence
          index[key] ||= product if key
        end
      end
    end

    def normalize(value) = value.to_s.strip.downcase

    def data
      @data ||= JSON.parse(DATA_DIR.join(CHANNELS.fetch(channel)[:file]).read)
    end
  end
end
