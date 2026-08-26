# frozen_string_literal: true

require "vips"

module Nsb
  # Turns the full-size scrape output into a committable set of product photos.
  #
  # The scraper downloads what newsouthbotanicals.com serves, which is whatever
  # was uploaded to WordPress -- several of them 6000x6000, 87MB across 83 files.
  # That is too much to commit and far more than a web catalog needs, so it stays
  # gitignored. But it cannot be fetched at deploy time either: the site's WAF
  # serves Render's IP a bot-challenge page instead of the image, with a fresh
  # body on every request.
  #
  # So the derivatives produced here ARE committed. At 1600px they come to about
  # 14MB, in the same order as the 6MB of B2BWave photos already in the repo, and
  # the import becomes deterministic and offline.
  class SitePhotoPreparer
    SOURCE_DIR = Rails.root.join("db/import_data/scraped_images")
    OUTPUT_DIR = Rails.root.join("db/import_data/site_photos")
    INDEX_PATH = OUTPUT_DIR.join("index.json")

    # Longest edge. Solidus renders these through Active Storage variants at a
    # few hundred pixels; 1600 leaves room for a product page to show detail
    # without carrying a print master around.
    MAX_EDGE = 1600
    QUALITY = 82

    Result = Struct.new(:written, :skipped, :source_bytes, :output_bytes, keyword_init: true) do
      def to_s
        "written=#{written} skipped=#{skipped} " \
          "#{(source_bytes / 1e6).round(1)}MB -> #{(output_bytes / 1e6).round(1)}MB"
      end
    end

    def call
      raise "no scrape output at #{SOURCE_DIR} -- run script/scrape_public_site_images.py" unless manifest_path.exist?

      OUTPUT_DIR.mkpath
      result = Result.new(written: 0, skipped: 0, source_bytes: 0, output_bytes: 0)
      index = {}

      manifest.fetch("blobs").each do |digest, blob|
        source = SOURCE_DIR.join(blob.fetch("file"))
        next unless source.exist?

        result.source_bytes += source.size
        bytes = downscale(source)
        target = OUTPUT_DIR.join(output_name(digest))

        if target.exist? && target.binread == bytes
          result.skipped += 1
        else
          target.binwrite(bytes)
          result.written += 1
        end

        result.output_bytes += bytes.bytesize
        index[digest] = {
          "file" => target.basename.to_s,
          "bytes" => bytes.bytesize,
          "sha256" => Digest::SHA256.hexdigest(bytes)
        }
      end

      INDEX_PATH.write(JSON.pretty_generate(index) + "\n")
      result
    end

    private

    def output_name(digest) = "#{digest[0, 16]}.jpg"

    # Everything lands as stripped JPEG: uniform, no metadata, no alpha to worry
    # about. The originals include PNGs of label panels, which flatten onto white
    # the same way the storefront renders them.
    def downscale(path)
      image = Vips::Image.new_from_file(path.to_s)
      image = image.flatten(background: 255) if image.has_alpha?

      longest = [ image.width, image.height ].max
      if longest > MAX_EDGE
        image = image.thumbnail_image((image.width * MAX_EDGE.to_f / longest).round)
      end

      image.write_to_buffer(".jpg", Q: QUALITY, strip: true)
    end

    def manifest_path = SOURCE_DIR.join("manifest.json")
    def manifest = @manifest ||= JSON.parse(manifest_path.read)
  end
end
