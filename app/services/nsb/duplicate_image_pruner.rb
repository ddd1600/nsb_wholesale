# frozen_string_literal: true

module Nsb
  # Removes the legacy copy of a photo that now exists twice on one product.
  #
  # Two pipelines fed this catalog: the B2BWave export brought a Cloudinary
  # resize of each product's front shot, and Nsb::SiteImageImporter later brought
  # the original upload from newsouthbotanicals.com. Byte-identical copies are
  # already skipped at import; these are the same picture at different sizes, so
  # only a perceptual comparison finds them.
  #
  # Two guards, both learned from the real catalog rather than assumed:
  #
  #   1. Only a legacy image is ever deleted, and only against a site image.
  #      Within the site's own gallery, distance zero does NOT mean duplicate --
  #      the "Suggested Use" and "Supplement Facts" panels of the same bottle
  #      score zero apart, because a difference hash sees one brown silhouette
  #      with a pale rectangle on it either way. Those are two deliberate photos
  #      and deleting one loses real information.
  #   2. The distance must be exactly zero. The nearest cross-pipeline false
  #      positive -- the peanut butter and mint chocolate tinctures, which differ
  #      only in a line of label text -- sits at distance two, so a rule of "<= 2"
  #      would delete the peanut butter product's own photograph.
  #
  # Every pair this currently matches was checked by eye before the rule was
  # settled on.
  class DuplicateImagePruner
    # B2BWave images were imported under their numeric source id ("245.jpg").
    # Site images carry a content-hash filename.
    LEGACY_FILENAME = /\A\d+\.\w+\z/

    Removal = Struct.new(:product, :removed, :kept, :bytes_freed, keyword_init: true)

    def initialize(dry_run: true)
      @dry_run = dry_run
    end

    def call
      removals = []

      Spree::Product.includes(master: { images: { attachment_attachment: :blob } }).find_each do |product|
        images = product.master.images.select { |image| image.attachment.attached? }
        legacy, from_site = images.partition { |image| filename(image).match?(LEGACY_FILENAME) }
        next if legacy.empty? || from_site.empty?

        site_hashes = from_site.to_h { |image| [ image, ImageFingerprint.dhash(bytes_for(image)) ] }

        legacy.each do |old_image|
          old_hash = ImageFingerprint.dhash(bytes_for(old_image))
          twin = from_site.find { |image| ImageFingerprint.hamming(old_hash, site_hashes[image])&.zero? }
          next unless twin

          removals << Removal.new(
            product: product,
            removed: describe(old_image),
            kept: describe(twin),
            bytes_freed: old_image.attachment.blob.byte_size
          )
          old_image.destroy unless @dry_run
        end
      end

      removals
    end

    private

    def filename(image)
      image.attachment.blob.filename.to_s
    end

    def bytes_for(image)
      image.attachment.blob.download
    end

    def describe(image)
      { id: image.id, filename: filename(image), bytes: image.attachment.blob.byte_size }
    end
  end
end
