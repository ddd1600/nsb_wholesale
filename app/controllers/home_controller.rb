# frozen_string_literal: true

class HomeController < StoreController
  include Nsb::PreloadsProductImages

  helper "spree/products"
  respond_to :html

  # Products shown below the podium, before the "everything else" list. Three
  # rows of three on desktop.
  SPOTLIGHT_SIZE = 9

  def index
    # The searcher pages at Spree::Config[:products_per_page] (12) by default,
    # which would silently truncate the ranking to whichever twelve products
    # happened to come back first. The whole catalog is 41 products, so ask for
    # all of it -- this is a wholesale portal, not a consumer store with a long
    # tail to paginate.
    @searcher = build_searcher(params.merge(include_images: true, per_page: 250))
    @products = preload_product_images(@searcher.retrieve_products)

    @ranking = Nsb::OrderFrequencyRanking.new(scope: @products, metric: params[:rank_by])
    @podium = @ranking.entries.first(3)
    @spotlight = @ranking.entries.drop(3).first(SPOTLIGHT_SIZE)
    @remaining = @ranking.entries.drop(3 + SPOTLIGHT_SIZE)
  end
end
