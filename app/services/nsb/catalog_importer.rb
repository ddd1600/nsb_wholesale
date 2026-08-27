# frozen_string_literal: true

module Nsb
  # Imports the B2BWave catalog from the reviewed intermediate files in
  # db/import_data into Solidus.
  #
  # Safe to re-run: every product is keyed on b2b_product_id, so a second run
  # updates in place rather than duplicating. This is the task that runs on
  # production, so it reads only committed local files -- no network, no
  # spreadsheet parsing, no dependency on B2BWave still being alive.
  #
  # Generate the input files with: python3 script/extract_b2bwave.py
  class CatalogImporter
    DATA_DIR = Rails.root.join("db/import_data")
    TAXONOMY_NAME = "Categories"

    Result = Struct.new(:created, :updated, :images_attached, :images_skipped, :failures, keyword_init: true) do
      def to_s
        "created=#{created} updated=#{updated} images_attached=#{images_attached} " \
          "images_skipped=#{images_skipped} failures=#{failures.size}"
      end
    end

    def initialize(data_dir: DATA_DIR, logger: Rails.logger)
      @data_dir = Pathname(data_dir)
      @logger = logger
      @result = Result.new(created: 0, updated: 0, images_attached: 0, images_skipped: 0, failures: [])
    end

    def call
      records = JSON.parse((@data_dir / "products.json").read).map { |record| apply_override(record) }
      say "importing #{records.size} products from #{@data_dir}"

      records.each do |record|
        # Per-record transaction: one bad row must not roll back a good import.
        ActiveRecord::Base.transaction { import_product(record) }
      rescue => error
        @result.failures << { sku: record["sku"], name: record["name"], error: error.message }
        say "  FAILED  #{record['sku']}  #{error.message}"
      end

      say "done: #{@result}"
      @result
    end

    private

    attr_reader :result

    # Corrections to known-bad source data, keyed by b2b_product_id. Kept out of
    # products.json so that file stays a faithful copy of the B2BWave export and
    # survives re-extraction. See db/import_data/product_overrides.json.
    def overrides
      @overrides ||= begin
        path = @data_dir / "product_overrides.json"
        path.exist? ? JSON.parse(path.read).except("_comment") : {}
      end
    end

    def apply_override(record)
      override = overrides[record["b2b_product_id"].to_s]
      return record if override.blank?

      # Underscore-prefixed keys are documentation for humans, not data.
      applied = override.reject { |key, _| key.start_with?("_") }
      say "  override #{record['b2b_product_id']}: #{applied.keys.join(', ')}"
      record.merge(applied)
    end

    def import_product(record)
      product = Spree::Product.find_or_initialize_by(b2b_product_id: record["b2b_product_id"])
      new_record = product.new_record?

      # Name and SKU are owned by Nsb::ProductConsolidator for products it folds
      # into variants, and by product_variants.json rather than the B2BWave
      # export. Two reasons not to write them here:
      #
      #   The rename would be undone on every import, so the storefront would
      #   show B2BWave's name until the consolidate step ran again.
      #
      #   The SKU would be REJECTED. Consolidation moves the size-specific SKU
      #   off the master and onto a variant, and Solidus enforces uniqueness --
      #   so restoring it here fails validation and takes the whole product row
      #   down with it. That is not hypothetical: it failed for all five gummy
      #   products the first time this pipeline was re-run end to end.
      product.name = record["name"] unless consolidation_managed?(record)
      product.description = record["description"]
      product.shipping_category = default_shipping_category
      # Four marketing items (brochures, posters) are genuinely free; Solidus
      # requires a non-null price, so they import at 0.0 rather than being skipped.
      product.price = record["price"] || 0.0
      product.available_on = record["active"] ? (product.available_on || Time.current) : nil
      # Products we no longer make. Spree::Product.available -- which the
      # storefront searcher builds on -- already filters on discontinue_on, so
      # setting it is all that is needed to take a line off the store. Nothing
      # is deleted: the order history still references these products, and the
      # admin can still see them.
      product.discontinue_on = record["discontinued"] ? (product.discontinue_on || Time.current) : nil
      product.save!

      # SKU lives on the master variant. Kept as-is from B2BWave, including the
      # placeholder "-", so admin still matches the old system; b2b_product_id
      # is what we actually key on.
      if record["sku"].present? && !consolidation_managed?(record) && product.master.sku != record["sku"]
        product.master.update!(sku: record["sku"])
      end

      assign_taxon(product, record["category_path"])
      attach_image(product, record["image"])

      new_record ? @result.created += 1 : @result.updated += 1
    end

    # b2b_product_ids that db/import_data/product_variants.json owns: the products
    # that survive a consolidation, and the ones folded into them.
    def consolidation_managed_ids
      @consolidation_managed_ids ||= begin
        path = @data_dir / "product_variants.json"
        if path.exist?
          config = JSON.parse(path.read)
          config.fetch("consolidations", []).flat_map do |spec|
            [ spec["keep"], *spec.fetch("supersedes", []).map { |entry| entry["b2b_product_id"] } ]
          end.compact.to_set
        else
          Set.new
        end
      end
    end

    def consolidation_managed?(record)
      consolidation_managed_ids.include?(record["b2b_product_id"])
    end

    def default_shipping_category
      @default_shipping_category ||= Spree::ShippingCategory.find_or_create_by!(name: "Default")
    end

    def taxonomy
      @taxonomy ||= Spree::Taxonomy.find_or_create_by!(name: TAXONOMY_NAME)
    end

    # "Tinctures/Original Formula" becomes Categories > Tinctures > Original Formula.
    def assign_taxon(product, category_path)
      return if category_path.blank?

      taxon = category_path.split("/").map(&:strip).reject(&:blank?).reduce(taxonomy.root) do |parent, name|
        parent.children.find_by(name: name) ||
          Spree::Taxon.create!(name: name, taxonomy: taxonomy, parent: parent)
      end

      # Assignment rather than <<, so re-running cannot pile up duplicates.
      product.taxons = [ taxon ] unless product.taxons.include?(taxon)
    end

    def attach_image(product, image_info)
      return if image_info.blank?

      path = @data_dir / "product_images" / image_info["file"]
      raise "image file missing: #{path}" unless path.exist?

      master = product.master
      attached = master.images.select { |image| image.attachment.attached? }

      # Idempotency without a checksum column: same filename and same byte
      # count means we already imported this exact file.
      if attached.any? { |image|
           image.attachment.blob.filename.to_s == image_info["file"] &&
             image.attachment.blob.byte_size == image_info["bytes"]
         }
        @result.images_skipped += 1
        return
      end

      # Leave the product alone if some other pipeline already gave it
      # photography. Nsb::SiteImageImporter attaches the originals from
      # newsouthbotanicals.com, which are higher resolution than the Cloudinary
      # copies in the B2BWave export; this importer used to destroy
      # images.first and put the low-res copy back, so running the two in the
      # wrong order silently downgraded the catalog.
      if attached.any?
        @result.images_skipped += 1
        return
      end
      # Pass an explicit hash rather than a File. Solidus normalises a bare IO
      # to {io:, filename: <absolute path>}, which stores the full local path as
      # the blob filename and leaves the handle's lifetime tied to this block --
      # Active Storage's content-type identification then hits a closed stream.
      # Reading into memory sidesteps both; the largest image here is under 1MB.
      master.images.create!(
        attachment: {
          io: StringIO.new(path.binread),
          filename: image_info["file"],
          content_type: Marcel::MimeType.for(path)
        }
      )
      @result.images_attached += 1
    end

    def say(message)
      @logger.info("[catalog-import] #{message}")
      puts message if $stdout.tty? || Rails.env.development?
    end
  end
end
