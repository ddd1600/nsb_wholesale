# frozen_string_literal: true

module TaxonCustomQueries
  def featured(limit = 3)
    all_products.featured.order('RANDOM()').limit(limit)
  end

  # Feeds "You May Also Like". Taxon#all_products includes discontinued
  # products, so the Delta 8 Gummies page was suggesting the old 10ct product
  # it replaced -- a dead page for customers, and a confusing duplicate for
  # admins, who can still open it.
  def all_products_except(product_ids)
    all_products.available.where.not(id: product_ids)
  end

  Spree::Taxon.prepend self
end
