# frozen_string_literal: true

require "rails_helper"

# Category pages list the most-ordered products first, ranked by the same
# wholesale order history as the homepage. The order history is matched by SKU,
# and the SKU the history knows best (the flavourless Delta 8 gummies) has been
# retired -- so this also guards the best seller against dropping to the bottom.
RSpec.describe "Category page order", type: :request do
  let!(:store) { create(:store) }
  let(:taxon) { create(:taxon, name: "Edibles") }

  def product_named(name, sku)
    create(:product, name: name, sku: sku, taxons: [ taxon ])
  end

  before do
    product_named("Aardvark Never Ordered", "NEVER-1")
    product_named("Advanced Extract", "2202")
    gummies = product_named("Delta 8 Gummies", "E-D8Gummies")
    create(:variant, product: gummies, sku: "E-D8Gummies10Ct").discard
  end

  it "puts the most-ordered first, even when its order-history SKU is retired" do
    get nested_taxons_path(taxon)

    expect(response).to have_http_status(:ok)
    names = Nokogiri::HTML(response.body).css("ul.products-grid li").map(&:text).map(&:squish)
    positions = ["Delta 8 Gummies", "Advanced Extract", "Aardvark Never Ordered"].map do |name|
      names.index { |text| text.include?(name) }
    end

    expect(positions).to all(be_present)
    expect(positions).to eq(positions.sort)
  end
end
