# frozen_string_literal: true

module Nsb
  # Folds pack sizes that B2BWave listed as separate products into one Solidus
  # product with variants.
  #
  # B2BWave has no variant concept, so "Supreme Formula Gummies (10ct)" and
  # "(30ct)" arrived as two unrelated products with two catalog pages. Customers
  # comparing sizes had to go back and forth between them, and the storefront
  # listing showed the same photo twice.
  #
  # Reads db/import_data/product_variants.json. Runs AFTER Nsb::CatalogImporter,
  # which is the thing that creates and updates the products this reorganises.
  #
  # Safe to re-run: variants are matched on SKU, so a second run updates prices
  # and positions in place rather than duplicating.
  #
  # Deliberately not folded into CatalogImporter. That importer's job is to be a
  # faithful projection of the B2BWave export, one source row to one product;
  # this is the opposite direction, many rows to one product, and mixing the two
  # would make the importer's idempotency much harder to reason about.
  class ProductConsolidator
    DATA_PATH = Rails.root.join("db/import_data/product_variants.json")

    Result = Struct.new(:products, :variants_created, :variants_updated, :superseded, :failures,
      keyword_init: true) do
      def to_s
        "products=#{products} variants_created=#{variants_created} " \
          "variants_updated=#{variants_updated} superseded=#{superseded} failures=#{failures.size}"
      end
    end

    def initialize(data_path: DATA_PATH, logger: Rails.logger)
      @data_path = Pathname(data_path)
      @logger = logger
    end

    def call
      # Built per call, not per instance: this runs to completion and reports
      # what THIS run did. Counting cumulatively across calls would make a
      # second run look like it had duplicated everything.
      @result = Result.new(products: 0, variants_created: 0, variants_updated: 0, superseded: 0, failures: [])

      config = JSON.parse(@data_path.read)
      option_type = find_or_create_option_type(config.fetch("option_type"))

      config.fetch("consolidations").each do |spec|
        # Per-consolidation transaction: one bad spec must not roll back a good one.
        ActiveRecord::Base.transaction { consolidate(spec, option_type) }
      rescue => error
        @result.failures << { keep: spec["keep"], name: spec["name"], error: error.message }
        say "  FAILED  #{spec['name']}: #{error.message}"
      end

      say "done: #{@result}"
      @result
    end

    private

    def find_or_create_option_type(spec)
      option_type = Spree::OptionType.find_or_initialize_by(name: spec.fetch("name"))
      option_type.presentation = spec.fetch("presentation")
      option_type.save!
      option_type
    end

    def consolidate(spec, option_type)
      product = Spree::Product.find_by!(b2b_product_id: spec.fetch("keep"))

      product.name = spec.fetch("name")
      # friendly_id keeps the slug it generated for the original name, so a
      # renamed product would otherwise keep a URL naming something that no
      # longer exists. Set explicitly rather than regenerated, so the URL is
      # reviewable in the data file rather than a side effect of the name.
      product.slug = spec.fetch("slug") if spec["slug"].present?
      product.save!

      # The option type must be on the product before variants can carry its
      # values, and assignment rather than << so a re-run cannot pile up
      # duplicates.
      product.option_types = [ option_type ] unless product.option_types.include?(option_type)

      # Superseding first, and the master SKU second, because both free up SKUs
      # that the variants below are about to claim. Solidus enforces uniqueness
      # across every variant that is not soft-deleted.
      spec.fetch("supersedes", []).each { |entry| supersede(entry) }
      release_master_sku(product, spec.fetch("master_sku"))

      spec.fetch("variants").each_with_index do |variant_spec, index|
        upsert_variant(product, option_type, variant_spec, position: index + 1)
      end

      @result.products += 1
      say "  #{spec.fetch('name')}: #{spec.fetch('variants').size} variants, " \
          "default #{spec.fetch('variants').first.fetch('presentation')}"
    end

    # The folded-away product keeps its name, its history and its admin page, and
    # stops being sellable. It cannot keep its SKU: that now belongs to a variant
    # of the surviving product, and Solidus would reject the variant as a
    # duplicate. product_variants.json records the original under "was_sku".
    def supersede(entry)
      product = Spree::Product.find_by(b2b_product_id: entry.fetch("b2b_product_id"))
      return if product.nil?

      # Blank, not nil: the column is NOT NULL, and Solidus's uniqueness
      # validation allows blank, so several superseded masters can share it.
      product.master.update!(sku: "") if product.master.sku.present?
      product.update!(discontinue_on: product.discontinue_on || Time.current)
      @result.superseded += 1
    end

    # A product with variants never sells its master, but the master still holds
    # a SKU -- and while it holds the size-specific one, the variant claiming that
    # SKU is a duplicate. Give it the parent SKU instead.
    def release_master_sku(product, master_sku)
      return if product.master.sku == master_sku

      product.master.update!(sku: master_sku)
    end

    def upsert_variant(product, option_type, spec, position:)
      option_value = find_or_create_option_value(option_type, spec.fetch("presentation"))

      variant = product.variants.find_by(sku: spec.fetch("sku")) ||
        product.variants.build(sku: spec.fetch("sku"))
      created = variant.new_record?

      variant.price = spec.fetch("price")
      variant.position = position
      # Assignment, so re-running with a changed size does not leave the old
      # value attached alongside the new one.
      variant.option_values = [ option_value ]
      variant.save!

      created ? @result.variants_created += 1 : @result.variants_updated += 1
      variant
    end

    def find_or_create_option_value(option_type, presentation)
      # name is the machine-readable key; Solidus shows presentation.
      name = presentation.parameterize
      value = option_type.option_values.find_or_initialize_by(name: name)
      value.presentation = presentation
      value.save!
      value
    end

    def say(message)
      @logger.info("[consolidate] #{message}")
      puts message if $stdout.tty? || Rails.env.development?
    end
  end
end
