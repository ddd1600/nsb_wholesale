# frozen_string_literal: true

module Nsb
  # Sets the default Spree::Store's identity.
  #
  # This is not cosmetic. Spree::Store#url is the host Solidus builds every
  # email link from, and #mail_from_address is the From on order confirmations
  # and account-claim emails -- the first thing 360 migrated customers will see.
  # Left at the seeded defaults they read "Sample Store" / store@example.com.
  #
  # Values come from the environment so they can be corrected on Render without
  # a deploy. Safe to re-run.
  class StoreConfigurator
    DEFAULTS = {
      name: "New South Botanicals Wholesale",
      # The retail WordPress site owns newsouthbotanicals.com, so the portal
      # needs its own host. Override with STORE_URL once the DNS record exists.
      url: "wholesale.newsouthbotanicals.com",
      mail_from_address: "connect@newsouthbotanicals.com",
      code: "nsb-wholesale"
    }.freeze

    def initialize(env: ENV, logger: Rails.logger)
      @env = env
      @logger = logger
    end

    def call
      store = Spree::Store.default
      raise "No default Spree::Store exists. Run bin/rails db:seed first." if store.nil? || store.new_record?

      store.name = @env.fetch("STORE_NAME", DEFAULTS[:name])
      store.url = @env.fetch("STORE_URL", DEFAULTS[:url])
      store.mail_from_address = @env.fetch("STORE_MAIL_FROM", DEFAULTS[:mail_from_address])
      store.code = @env.fetch("STORE_CODE", DEFAULTS[:code]) if store.code.blank? || store.code == "sample-store"

      changes = store.changes
      store.save!

      say(changes.any? ? "updated: #{changes.keys.join(', ')}" : "already up to date")
      store
    end

    private

    def say(message)
      @logger.info("[store-config] #{message}")
      puts "store: #{message}"
    end
  end
end
