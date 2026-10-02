# frozen_string_literal: true

module Nsb
  # Orders a product listing most-ordered first, using the same wholesale
  # order history that ranks the homepage (Nsb::DemandRanking, units sold).
  # Products with no order history follow, alphabetically.
  #
  # Sorted in Ruby rather than SQL on purpose. Solidus's searcher selects
  # DISTINCT, and Postgres refuses to ORDER BY an expression that is not in a
  # DISTINCT select list, so a "rank" ordering cannot be bolted on without
  # rewriting Solidus's query. A category holds a dozen-odd products, so
  # loading them all and paginating the sorted array costs nothing.
  module SortsProductsByDemand
    extend ActiveSupport::Concern

    private

    def sort_products_by_demand(products)
      Kaminari.paginate_array(Nsb::SortsProductsByDemand.sort(products.except(:limit, :offset).to_a))
        .page(products.current_page)
        .per(products.limit_value)
    end

    def self.sort(products)
      position = Nsb::DemandRanking.new.entries.each_with_index.to_h { |entry, index| [ entry.product.id, index ] }
      products.sort_by { |product| [ position.fetch(product.id, position.size), product.name.downcase ] }
    end
  end
end
