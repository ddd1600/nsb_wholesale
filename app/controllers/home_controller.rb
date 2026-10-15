# frozen_string_literal: true

class HomeController < StoreController
  include Nsb::PreloadsProductImages

  helper "spree/products"
  respond_to :html

  # Products shown below the podium, before the "everything else" list. Three
  # rows of three on desktop.
  SPOTLIGHT_SIZE = 9

  # Hand-picked products shown between the podium and the spotlight, in this
  # order, chosen by the operator (2026-10-15). Master SKUs rather than names or
  # slugs, because products get renamed. A SKU that is missing or discontinued
  # is skipped rather than raising, so the homepage never breaks over this.
  FEATURED_SKUS = %w[
    E-IsoSupremeGummies
    T-D8AdvancedFormula
  ].freeze

  # The front door. A visitor with no account is asked which kind of visitor
  # they are before being shown a catalog they cannot buy from.
  before_action :redirect_anonymous_to_welcome, only: :index

  def index
    # The searcher pages at Spree::Config[:products_per_page] (12) by default,
    # which would silently truncate the ranking to whichever twelve products
    # happened to come back first. The whole catalog is ~40 products, so ask for
    # all of it -- this is a wholesale portal, not a consumer store with a long
    # tail to paginate.
    @searcher = build_searcher(params.merge(include_images: true, per_page: 250))
    @products = preload_product_images(@searcher.retrieve_products)

    @ranking = Nsb::DemandRanking.new(
      scope: @products,
      channel: params[:channel],
      metric: params[:rank_by]
    )
    @podium = @ranking.entries.first(3)
    @spotlight = @ranking.entries.drop(3).first(SPOTLIGHT_SIZE)
    @remaining = @ranking.entries.drop(3 + SPOTLIGHT_SIZE)
    @featured = featured_products
  end

  private

  # Picked out of @products so they arrive with images preloaded and only if
  # they are still available.
  def featured_products
    product_ids = Spree::Variant.where(is_master: true, sku: FEATURED_SKUS).pluck(:sku, :product_id).to_h
    FEATURED_SKUS.filter_map { |sku| @products.find { |product| product.id == product_ids[sku] } }
  end

  def redirect_anonymous_to_welcome
    redirect_to welcome_path if spree_current_user.blank?
  end
end
