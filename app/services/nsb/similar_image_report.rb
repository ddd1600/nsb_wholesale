# frozen_string_literal: true

module Nsb
  # Nominates visually similar image pairs within each product's gallery, so a
  # person can decide whether they are duplicates.
  #
  # This deliberately reports rather than deletes. See Nsb::ImageFingerprint for
  # why a distance threshold cannot be trusted on this catalog: white-background
  # bottle shots from one product family score as close together as true
  # duplicates do.
  class SimilarImageReport
    # Wide on purpose. This is a shortlist for human eyes, so a few false
    # nominations cost nothing and a missed duplicate costs the whole point.
    DEFAULT_THRESHOLD = 8

    Pair = Struct.new(:product, :keep, :candidate, :distance, keyword_init: true)

    def initialize(threshold: DEFAULT_THRESHOLD)
      @threshold = threshold
    end

    def call
      pairs = []

      Spree::Product.includes(master: { images: { attachment_attachment: :blob } }).find_each do |product|
        images = product.master.images.select { |image| image.attachment.attached? }
        next if images.size < 2

        fingerprints = images.map { |image| [ image, ImageFingerprint.dhash(image.attachment.blob.download) ] }

        fingerprints.combination(2).each do |(first, first_hash), (second, second_hash)|
          distance = ImageFingerprint.hamming(first_hash, second_hash)
          next if distance.nil? || distance > @threshold

          pairs << Pair.new(product: product, keep: first, candidate: second, distance: distance)
        end
      end

      pairs.sort_by(&:distance)
    end
  end
end
