# frozen_string_literal: true

module Nsb
  # Generates the Active Storage variants the storefront asks for, ahead of time.
  #
  # Solidus resolves a style lazily: the first request needing one runs it through
  # libvips and writes the result to storage. With blobs in PostgreSQL and ~50
  # images on the homepage, the first page load after an image import took 13
  # seconds while every later load took one.
  #
  # At roughly one order a day, "the first visitor pays" means most visitors pay
  # -- there is rarely anyone ahead of them to warm it. So do it at import time,
  # where nobody is waiting.
  #
  # Deliberately goes through Spree::ActiveStorageAdapter::Attachment#variant,
  # the same call the views make, rather than rebuilding the transformation hash.
  # A variant is looked up by a digest of that hash, so a reimplementation that
  # drifted by one key would warm variants nothing ever asks for and the page
  # would still be slow -- while every counter here said it had worked.
  class ImageVariantWarmer
    # What the storefront renders: :small and :mini on the homepage and listings,
    # :product and :large on the product page gallery.
    STYLES = %i[mini small product large].freeze

    Result = Struct.new(:generated, :existing, :failures, keyword_init: true) do
      def to_s = "generated=#{generated} already_present=#{existing} failures=#{failures.size}"
    end

    def initialize(styles: STYLES, logger: Rails.logger)
      @styles = styles
      @logger = logger
      @result = Result.new(generated: 0, existing: 0, failures: [])
    end

    def call
      # transform.active_storage fires only when libvips actually runs, which is
      # how we tell a generated variant from one that was already there.
      transformed = 0
      subscriber = ActiveSupport::Notifications.subscribe("transform.active_storage") { transformed += 1 }

      Spree::Image.includes(attachment_attachment: { blob: :variant_records }).find_each do |image|
        next unless image.attachment.attached?

        @styles.each do |style|
          before = transformed
          warm(image, style)
          transformed > before ? @result.generated += 1 : @result.existing += 1
        end
      end

      @result
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end

    private

    def warm(image, style)
      image.attachment.variant(style)
    rescue StandardError => e
      @result.failures << { image_id: image.id, style: style, error: e.message }
      @logger.warn("[image-warm] image #{image.id} #{style}: #{e.message}")
    end
  end
end
