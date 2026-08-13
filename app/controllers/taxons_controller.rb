# frozen_string_literal: true

class TaxonsController < StoreController
  include Nsb::PreloadsProductImages

  helper 'spree/taxons', 'spree/products', 'taxon_filters'

  before_action :load_taxon, only: [:show]

  respond_to :html

  def show
    @searcher = build_searcher(params.merge(taxon: @taxon.id, include_images: true))
    # include_images only preloads Spree::Image; the Active Storage chain behind
    # each one still N+1s without this.
    @products = preload_product_images(@searcher.retrieve_products)
  end

  private

  def load_taxon
    @taxon = Spree::Taxon.friendly.find(params[:id])
    redirect_to nested_taxons_path(@taxon), status: :moved_permanently if params[:id] != @taxon.permalink
  end

  def accurate_title
    if @taxon
      @taxon.seo_title
    else
      super
    end
  end
end
