# frozen_string_literal: true

module Nsb
  # Attaches product photos scraped from the public newsouthbotanicals.com
  # storefront to the matching wholesale products.
  #
  # Input is db/import_data/scraped_images/, produced by
  # script/scrape_public_site_images.py -- image files plus a manifest mapping
  # public SKUs to them. Nothing here talks to the network.
  #
  # Matching is by SKU only. The public site and the wholesale catalog share SKUs
  # for everything sold in both places, and the alternative -- matching on product
  # names -- is actively unsafe here: the site sells a "Mint Chocolate ... Original
  # Hemp Flower Extract (450MG)" and we sell an "Advanced Hemp Flower Extract
  # (1400MG) - Mint Chocolate", which any similarity score cheerfully conflates.
  # The handful of products whose public listing exposes no SKU are linked by hand
  # in sku_overrides.json.
  #
  # Safe to re-run: an image already on the product is skipped rather than
  # duplicated.
  class SiteImageImporter
    DATA_DIR = Rails.root.join("db/import_data/scraped_images")
    MANIFEST_PATH = DATA_DIR.join("manifest.json")
    OVERRIDES_PATH = DATA_DIR.join("sku_overrides.json")

    # Deduplication here is byte-exact only, and deliberately so. Visual
    # near-duplicates do exist -- several products already carry a Cloudinary
    # resize of the very shot we just downloaded -- but on this catalog a
    # perceptual hash cannot tell them apart from genuinely different photos:
    # measured over the real images, same-photo pairs and different-photo pairs
    # both land in the 0-7 bit range, because almost everything is the same white
    # bottle on the same white background. Silently dropping the peanut butter
    # tincture's own front shot because it looks like the mint chocolate one is a
    # worse outcome than an extra image in a gallery. Nsb::SimilarImageReport
    # nominates candidates for a person to review instead.

    Result = Struct.new(
      :attached, :skipped_identical,
      :products_matched, :products_unmatched, :failures,
      keyword_init: true
    ) do
      def to_s
        "attached=#{attached} skipped_identical=#{skipped_identical} " \
          "products_matched=#{products_matched.size} " \
          "products_unmatched=#{products_unmatched.size} failures=#{failures.size}"
      end
    end

    def initialize(dry_run: false, logger: Rails.logger)
      @dry_run = dry_run
      @logger = logger
      @result = Result.new(
        attached: 0, skipped_identical: 0,
        products_matched: [], products_unmatched: [], failures: []
      )
    end

    def call
      raise "manifest missing: #{MANIFEST_PATH} -- run script/scrape_public_site_images.py" unless MANIFEST_PATH.exist?

      Spree::Product.includes(master: :images).find_each do |product|
        digests = digests_for(product)

        if digests.empty?
          @result.products_unmatched << { sku: sku_for(product), name: product.name }
          next
        end

        attached = import(product, digests)
        @result.products_matched << { sku: sku_for(product), name: product.name, attached: attached }
      rescue StandardError => e
        @result.failures << { sku: sku_for(product), name: product.name, error: e.message }
      end

      @result
    end

    private

    attr_reader :dry_run

    def sku_for(product)
      product.master.sku.to_s.strip
    end

    # Image digests for this product, in the order the public site presents them.
    def digests_for(product)
      sku = sku_for(product)
      return [] if sku.blank?

      by_sku = manifest.fetch("skus")[sku]
      return by_sku.fetch("images") if by_sku

      public_name = overrides[sku]
      return [] if public_name.blank?

      entry = manifest.fetch("catalog").find { |row| row["name"] == public_name }
      unless entry
        raise "sku_overrides.json points #{sku} at \"#{public_name}\", which is not in the manifest"
      end

      entry.fetch("images")
    end

    def import(product, digests)
      master = product.master
      # Checksums of what the product already has, grown as we attach so the same
      # file cannot land twice in one run either.
      seen_checksums = master.images.filter_map { |image| image.attachment.blob&.checksum }

      attached = 0

      digests.each do |digest|
        blob = manifest.fetch("blobs").fetch(digest)
        path = DATA_DIR.join(blob.fetch("file"))
        raise "image file missing: #{path}" unless path.exist?

        bytes = path.binread

        checksum = Digest::MD5.base64digest(bytes)
        if seen_checksums.include?(checksum)
          @result.skipped_identical += 1
          next
        end

        unless dry_run
          # An explicit hash rather than a bare IO: Solidus normalises an IO to
          # {io:, filename: <absolute path>}, storing the full local path as the
          # blob filename and tying the handle's lifetime to this block, after
          # which content-type detection reads a closed stream.
          master.images.create!(
            attachment: {
              io: StringIO.new(bytes),
              filename: blob.fetch("file"),
              content_type: Marcel::MimeType.for(path)
            }
          )
        end

        seen_checksums << checksum
        @result.attached += 1
        attached += 1
      end

      attached
    end

    def manifest
      @manifest ||= JSON.parse(MANIFEST_PATH.read)
    end

    def overrides
      @overrides ||= OVERRIDES_PATH.exist? ? JSON.parse(OVERRIDES_PATH.read).except("_comment") : {}
    end

    def say(message)
      @logger.info("[site-images] #{message}")
    end
  end
end
