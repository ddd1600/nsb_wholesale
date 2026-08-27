# frozen_string_literal: true

module Nsb
  # Attaches the current certificates of analysis to their products, above the
  # lab test images they supersede.
  #
  # Position is the whole point. A COA is the one image on these pages a customer
  # reads for a fact rather than a look, and a 2018 lab test sitting above a 2025
  # one is worse than no lab test at all -- it is a wrong answer presented
  # confidently. So the new certificate goes directly above the old one, and the
  # old one is kept rather than deleted: superseded is not the same as wrong, and
  # a customer may hold a link to it.
  #
  # Reads db/import_data/lab_tests/manifest.json. Run AFTER Nsb::SiteImageImporter
  # and Nsb::ProductConsolidator, both of which move images and products around.
  #
  # Safe to re-run: matched on filename, so a second run repositions rather than
  # attaching a second copy.
  class LabTestImporter
    DATA_DIR = Rails.root.join("db/import_data/lab_tests")
    MANIFEST_NAME = "manifest.json"

    Result = Struct.new(:attached, :skipped_present, :repositioned, :products, :failures, keyword_init: true) do
      def to_s
        "attached=#{attached} already_present=#{skipped_present} " \
          "repositioned=#{repositioned} products=#{products} failures=#{failures.size}"
      end
    end

    def initialize(data_dir: DATA_DIR, logger: Rails.logger)
      @data_dir = Pathname(data_dir)
      @logger = logger
    end

    def call
      @result = Result.new(attached: 0, skipped_present: 0, repositioned: 0, products: 0, failures: [])

      manifest.fetch("certificates").each do |certificate|
        certificate.fetch("b2b_product_ids").each do |b2b_product_id|
          # Per-product transaction: one missing product must not roll back the
          # certificates already attached.
          ActiveRecord::Base.transaction { attach(certificate, b2b_product_id) }
        rescue => error
          @result.failures << { coa: certificate["coa"], b2b_product_id: b2b_product_id, error: error.message }
          say "  FAILED  #{certificate['coa']} -> #{b2b_product_id}: #{error.message}"
        end
      end

      say "done: #{@result}"
      @result
    end

    private

    def attach(certificate, b2b_product_id)
      product = Spree::Product.find_by!(b2b_product_id: b2b_product_id)
      master = product.master

      certificate.fetch("files").each do |filename|
        path = @data_dir / filename
        raise "lab test file missing: #{path}" unless path.exist?

        if existing_filenames(master).include?(filename)
          @result.skipped_present += 1
          next
        end

        # An explicit hash rather than a bare IO, for the same reason the other
        # importers do it: Solidus normalises an IO to {io:, filename: <absolute
        # path>}, storing the local path as the blob filename and closing the
        # handle before content-type detection reads it.
        master.images.create!(
          attachment: {
            io: StringIO.new(path.binread),
            filename: filename,
            content_type: Marcel::MimeType.for(path)
          }
        )
        @result.attached += 1
      end

      @result.repositioned += 1 if reposition(master, certificate.fetch("files"))
      @result.products += 1
      say "  #{certificate.fetch('coa')} -> #{product.name}"
    end

    def existing_filenames(master)
      master.images.filter_map { |image| image.attachment.blob&.filename&.to_s }
    end

    # Put the new certificates immediately above the lab test they supersede,
    # leaving everything else in the order it was already in. Product photography
    # stays first; a COA is a reference, not the shot that sells the product.
    #
    # If the product has no superseded lab test, the certificates go last, which
    # is the same place they would land by being newest.
    def reposition(master, new_files)
      images = master.images.select { |image| image.attachment.attached? }.sort_by(&:position)
      by_name = images.group_by { |image| image.attachment.blob.filename.to_s }

      new_images = new_files.filter_map { |filename| by_name[filename]&.first }
      return false if new_images.empty?

      others = images - new_images
      insert_at = others.index { |image| superseded_files.include?(image.attachment.blob.filename.to_s) } ||
        others.size

      ordered = others.first(insert_at) + new_images + others.drop(insert_at)
      return false if ordered.map(&:id) == images.map(&:id)

      ordered.each_with_index { |image, index| image.update_column(:position, index + 1) }
      true
    end

    def superseded_files
      @superseded_files ||= manifest.fetch("superseded_lab_test_files").to_set
    end

    def manifest
      # Derived from data_dir, not a constant: the spec points both at a
      # temporary directory, and a manifest read from somewhere other than the
      # images it describes would silently drift from them.
      @manifest ||= JSON.parse((@data_dir / MANIFEST_NAME).read)
    end

    def say(message)
      @logger.info("[lab-tests] #{message}")
      puts message if $stdout.tty? || Rails.env.development?
    end
  end
end
