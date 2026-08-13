# frozen_string_literal: true

module Nsb
  # Eager-loads the Active Storage chain behind product images.
  #
  # Solidus's searcher does `preload(master: :images)` when include_images is
  # set, which loads the Spree::Image rows but stops there. Rendering each image
  # then issues its own queries for the attachment, the blob and the variant
  # record -- so a 30-product category page fired well over 200 queries, roughly
  # seven per product.
  #
  # This is not a development-only problem: the query count is the same in
  # production, it just hides behind faster hardware.
  #
  # Preloading after retrieval rather than changing the searcher keeps this
  # additive -- Solidus keeps owning the product query, and pagination still
  # applies before we touch attachments.
  module PreloadsProductImages
    extend ActiveSupport::Concern

    IMAGE_ASSOCIATIONS = {
      master: {
        images: {
          attachment_attachment: {
            blob: :variant_records
          }
        }
      }
    }.freeze

    private

    def preload_product_images(products)
      records = products.to_a
      return products if records.empty?

      ActiveRecord::Associations::Preloader.new(
        records: records,
        associations: IMAGE_ASSOCIATIONS
      ).call

      products
    end
  end
end
