# frozen_string_literal: true

require "rails_helper"

# "You May Also Like" on the Delta 8 Gummies page was suggesting the old 10ct
# product that the page replaced, because Taxon#all_products includes
# discontinued products.
RSpec.describe "Spree::Product#similar_products" do
  let(:taxon) { create(:taxon) }
  let!(:product) { create(:product, taxons: [ taxon ]) }
  let!(:sibling) { create(:product, taxons: [ taxon ]) }
  let!(:retired) { create(:product, taxons: [ taxon ], discontinue_on: 1.day.ago) }

  it "never suggests a product that is no longer on sale" do
    expect(product.similar_products).to eq([ sibling ])
  end
end
