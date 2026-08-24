# frozen_string_literal: true

module Nsb
  # Ranks the current Solidus catalog by historical demand, measured either in
  # units sold or in dollar sales.
  #
  # The numbers are not computed from Spree::Order -- this store has no order
  # history of its own yet. They come from the legacy B2BWave portal's order
  # export (b2bwave_source_files/orders_2026-08-11.xlsx), pre-aggregated by
  # script/rank_products_by_orders.py into the JSON file this class reads.
  # Re-run that script to refresh the numbers.
  #
  # Reading a checked-in file rather than querying is deliberate: the source data
  # is historical and frozen, so there is nothing to recompute at request time.
  class OrderFrequencyRanking
    DATA_PATH = Rails.root.join("db/import_data/product_order_frequency.json")

    # The two ways a buyer can sort the homepage. :units is the default because
    # "how much of this moves" is the reorder question; :sales answers a
    # different one, and the two disagree -- the 10ct gummies lead on units, the
    # 30ct on dollars.
    METRICS = {
      units: { field: "units", label: "Units sold", share_suffix: "of units sold" },
      sales: { field: "revenue", label: "Dollar sales", share_suffix: "of sales" }
    }.freeze

    DEFAULT_METRIC = :units

    # Coerces anything (a query param, nil, junk) to a supported metric.
    def self.metric_for(value)
      key = value.to_s.downcase.to_sym
      METRICS.key?(key) ? key : DEFAULT_METRIC
    end

    # One catalog product plus its legacy demand. `rank` is the position within
    # *this* list, not the raw export -- discontinued products are dropped before
    # ranking, so the raw ranks would have gaps.
    Entry = Struct.new(:product, :rank, :units, :revenue, :share, keyword_init: true)

    attr_reader :metric

    def initialize(scope: Spree::Product.all, metric: DEFAULT_METRIC)
      @scope = scope
      @metric = self.class.metric_for(metric)
    end

    def metric_label
      METRICS.fetch(metric)[:label]
    end

    # "of units sold" / "of sales" -- the tail of every percentage on the page.
    def share_suffix
      METRICS.fetch(metric)[:share_suffix]
    end

    # Ranked best-to-worst by the selected metric. Only products that still exist
    # in the catalog appear: 14 of the 46 products in the export have been
    # discontinued, and offering a customer something we cannot sell is worse
    # than a shorter list. Products with no history at all never appear either --
    # there is nothing to rank them by.
    def entries
      @entries ||= begin
        field = METRICS.fetch(metric)[:field]

        matched.sort_by { |_product, row| -row.fetch(field).to_f }.each_with_index.map do |(product, row), index|
          Entry.new(
            product: product,
            rank: index + 1,
            units: row["units"],
            revenue: row["revenue"],
            share: total.positive? ? row.fetch(field).to_f / total : 0.0
          )
        end
      end
    end

    # Scales the frequency bars. Everything is measured against the leader
    # rather than against 100%, otherwise every bar below the top few is an
    # invisible sliver.
    def max_share
      entries.first&.share || 0.0
    end

    def first_order_date
      Date.parse(data.fetch("first_order_date"))
    end

    def last_order_date
      Date.parse(data.fetch("last_order_date"))
    end

    private

    attr_reader :scope

    # Denominator for every percentage on the page: the whole export, including
    # products since discontinued. Shares therefore sum to somewhat less than
    # 100%, which is the honest answer -- the missing slice is real demand we no
    # longer sell.
    def total
      @total ||= data.fetch("products").sum { |row| row.fetch(METRICS.fetch(metric)[:field]).to_f }
    end

    # Export rows paired with the catalog product they still map to.
    def matched
      @matched ||= begin
        by_sku, by_name = catalog_indexes

        pairs = data.fetch("products").filter_map do |row|
          product = by_sku[row["sku"].to_s.strip.presence] || by_name[normalize(row["name"])]
          next if product.nil?

          [ product, row ]
        end

        # A catalog product can be reached by two export rows (e.g. a SKU left
        # blank on some historical lines). Keep the first, which is the stronger.
        pairs.uniq { |product, _row| product.id }
      end
    end

    def catalog_indexes
      products = scope.to_a
      by_sku = products.index_by { |product| product.master.sku.to_s.strip.presence }
      by_name = products.index_by { |product| normalize(product.name) }
      [ by_sku, by_name ]
    end

    def normalize(value)
      value.to_s.strip.downcase
    end

    def data
      @data ||= JSON.parse(DATA_PATH.read)
    end
  end
end
