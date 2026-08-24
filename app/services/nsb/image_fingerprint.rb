# frozen_string_literal: true

require "vips"

module Nsb
  # Difference hashes for product photos, used to spot the same picture arriving
  # twice through different pipelines (a Cloudinary resize from the B2BWave
  # export vs. the original upload on newsouthbotanicals.com).
  #
  # Read the caveat before trusting a small distance: this catalog is mostly
  # white-background bottle shots from one product family, so *genuinely
  # different* photos routinely score as low as 2 bits apart -- the mint
  # chocolate and peanut butter tinctures differ only in a word on the label.
  # Distance is therefore good enough to nominate duplicates for a human to look
  # at, and not good enough to delete anything automatically.
  module ImageFingerprint
    module_function

    # 64-bit difference hash: greyscale, squash to 9x8, record whether each pixel
    # is brighter than the one to its right. Survives rescaling and re-encoding.
    def dhash(bytes, size: 8)
      return nil if bytes.blank?

      image = Vips::Image.new_from_buffer(bytes, "")
      image = image.flatten(background: 255) if image.has_alpha?
      grid = image.colourspace("b-w").thumbnail_image(size + 1, height: size, size: :force)

      bits = grid.to_a.flat_map do |row|
        row.each_cons(2).map { |left, right| left.first > right.first ? 1 : 0 }
      end
      bits.join.to_i(2)
    rescue Vips::Error, StandardError
      nil
    end

    def hamming(one, two)
      return nil if one.nil? || two.nil?

      (one ^ two).to_s(2).count("1")
    end
  end
end
