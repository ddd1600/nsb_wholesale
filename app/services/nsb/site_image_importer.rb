# frozen_string_literal: true

require "net/http"

module Nsb
  # Attaches product photos scraped from the public newsouthbotanicals.com
  # storefront to the matching wholesale products.
  #
  # db/import_data/scraped_images/manifest.json says which images a SKU gets and
  # in what order. The bytes come from the first of these that has them:
  #
  #   1. db/import_data/site_photos/ -- 1600px derivatives, committed, produced
  #      by Nsb::SitePhotoPreparer. This is what production uses.
  #   2. db/import_data/scraped_images/ -- the full-size scrape output, gitignored
  #      because it is 87MB and a git repo never forgets a blob.
  #   3. The source URL the manifest recorded, verified against the SHA-256 it
  #      keys the image by.
  #
  # Fetching (3) was tried as production's path and does not work: the site's WAF
  # answers Render's IP with a bot-challenge page rather than the image, served
  # as HTTP 200 with a fresh body every request. The checksum guard caught it --
  # 28 challenge pages refused rather than attached as product photos -- which is
  # why the committed derivatives exist. The URL path is kept for machines the
  # site will actually talk to.
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
    PHOTOS_DIR = Rails.root.join("db/import_data/site_photos")
    PHOTO_INDEX_PATH = PHOTOS_DIR.join("index.json")
    MANIFEST_PATH = DATA_DIR.join("manifest.json")
    OVERRIDES_PATH = DATA_DIR.join("sku_overrides.json")

    # A descriptive bot user agent is rejected outright by the site's WAF.
    BROWSER_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
                         "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"

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
      :attached, :skipped_identical, :downloaded,
      :products_matched, :products_unmatched, :failures,
      keyword_init: true
    ) do
      def to_s
        "attached=#{attached} downloaded=#{downloaded} " \
          "skipped_identical=#{skipped_identical} " \
          "products_matched=#{products_matched.size} " \
          "products_unmatched=#{products_unmatched.size} failures=#{failures.size}"
      end
    end

    def initialize(dry_run: false, logger: Rails.logger)
      @dry_run = dry_run
      @logger = logger
      @result = Result.new(
        attached: 0, skipped_identical: 0, downloaded: 0,
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
        reordered = reorder(product, digests)
        @result.products_matched << {
          sku: sku_for(product), name: product.name, attached: attached, reordered: reordered
        }
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

      # Filenames are content-derived (the SHA-256 prefix), so a product that
      # already carries this filename already carries these exact bytes. Checked
      # before fetching, so a re-run costs no downloads.
      seen_filenames = master.images.filter_map { |image| image.attachment.blob&.filename&.to_s }

      digests.each do |digest|
        blob = manifest.fetch("blobs").fetch(digest)
        filename = blob.fetch("file")

        if seen_filenames.include?(filename)
          @result.skipped_identical += 1
          next
        end

        bytes = bytes_for(digest, blob)

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
              filename: filename,
              content_type: Marcel::MimeType.for(StringIO.new(bytes))
            }
          )
        end

        seen_checksums << checksum
        seen_filenames << filename
        @result.attached += 1
        attached += 1
      end

      attached
    end

    # The image bytes, from the committed derivative, then the full-size scrape
    # output, then the network.
    def bytes_for(digest, blob)
      prepared = photo_index[digest]
      if prepared
        path = PHOTOS_DIR.join(prepared.fetch("file"))
        if path.exist?
          bytes = path.binread
          actual = Digest::SHA256.hexdigest(bytes)
          unless actual == prepared.fetch("sha256")
            raise "#{path.basename} does not match site_photos/index.json " \
                  "(expected #{prepared.fetch('sha256')[0, 12]}, got #{actual[0, 12]})"
          end

          return bytes
        end
      end

      path = DATA_DIR.join(blob.fetch("file"))
      return path.binread if path.exist?

      url = blob.fetch("sources").first
      raise "no local file and no source URL for image #{digest}" if url.blank?

      bytes = download(url)

      # The manifest keys images by SHA-256, so this both detects a truncated
      # download and catches the source URL having been repointed at a different
      # picture since the scrape. Attaching the wrong photo silently is worse
      # than failing.
      actual = Digest::SHA256.hexdigest(bytes)
      unless actual == digest
        # Say what actually arrived. A WAF challenge page comes back as HTTP 200
        # with a body that differs every request, and "checksum mismatch" alone
        # sends you looking for a changed image instead of a blocked request.
        raise "#{url} did not return the expected image " \
              "(expected sha #{digest[0, 12]}, got #{actual[0, 12]}; " \
              "#{bytes.bytesize} bytes, looks like #{sniff(bytes)})"
      end

      @result.downloaded += 1
      bytes
    end

    # Enough to tell an image from an error page in a failure message.
    def sniff(bytes)
      head = bytes[0, 16].to_s
      return "JPEG" if head.start_with?("\xFF\xD8\xFF".b)
      return "PNG" if head.start_with?("\x89PNG".b)
      return "GIF" if head.start_with?("GIF8")
      return "WEBP" if head[8, 4] == "WEBP"
      return "HTML (an error or challenge page, not an image)" if head.downcase.include?("<!doctype") ||
                                                                  head.downcase.include?("<html")

      "unrecognised data"
    end

    def download(url)
      uri = URI.parse(url)
      # The site sits behind a WAF that 403s anything not shaped like a browser.
      request = Net::HTTP::Get.new(uri, "User-Agent" => BROWSER_USER_AGENT)

      response = Net::HTTP.start(
        uri.host, uri.port, use_ssl: uri.scheme == "https",
        open_timeout: 10, read_timeout: 60
      ) { |http| http.request(request) }

      unless response.is_a?(Net::HTTPSuccess)
        raise "GET #{url} returned #{response.code}"
      end

      response.body
    end

    # Put the product's images back into the order the public site shows them,
    # so the site's featured image is the one the storefront leads with.
    #
    # Worth doing on every run, not just on first import: Nsb::CatalogImporter
    # attaches the B2BWave copy of a photo, and a prune of that copy afterwards
    # leaves whatever survives in an order nobody chose. Anything not in the
    # manifest keeps its relative order, after the site images.
    def reorder(product, digests)
      wanted = digests.filter_map { |digest| manifest.fetch("blobs")[digest]&.fetch("file") }
      images = product.master.images.select { |image| image.attachment.attached? }

      ranked = images.sort_by do |image|
        index = wanted.index(image.attachment.blob.filename.to_s)
        [ index ? 0 : 1, index || 0, image.position ]
      end
      return false if ranked.map(&:id) == images.sort_by(&:position).map(&:id)
      return true if dry_run

      ranked.each_with_index do |image, index|
        image.update_column(:position, index + 1)
      end
      true
    end

    def manifest
      @manifest ||= JSON.parse(MANIFEST_PATH.read)
    end

    def photo_index
      @photo_index ||= PHOTO_INDEX_PATH.exist? ? JSON.parse(PHOTO_INDEX_PATH.read) : {}
    end

    def overrides
      @overrides ||= OVERRIDES_PATH.exist? ? JSON.parse(OVERRIDES_PATH.read).except("_comment") : {}
    end

    def say(message)
      @logger.info("[site-images] #{message}")
    end
  end
end
