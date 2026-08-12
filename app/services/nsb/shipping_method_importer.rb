# frozen_string_literal: true

module Nsb
  # Creates Solidus shipping methods from the rows B2BWave modelled as products.
  #
  # B2BWave had no first-class shipping, so the previous operator sold "UPS
  # Ground Shipping" as a $24 catalog item the customer added to their cart.
  # Solidus has real shipping methods, so these are deliberately NOT imported as
  # products (see script/extract_b2bwave.py, which splits them out).
  #
  # Each becomes a flat-rate method at the same price the customer paid before,
  # so nothing changes for them at checkout.
  #
  # Safe to re-run: matched on name.
  class ShippingMethodImporter
    DATA_FILE = Rails.root.join("db/import_data/shipping_methods.json")

    Result = Struct.new(:created, :updated, :failures, keyword_init: true) do
      def to_s = "created=#{created} updated=#{updated} failures=#{failures.size}"
    end

    def initialize(data_file: DATA_FILE, logger: Rails.logger)
      @data_file = Pathname(data_file)
      @logger = logger
      @result = Result.new(created: 0, updated: 0, failures: [])
    end

    def call
      records = JSON.parse(@data_file.read)
      say "importing #{records.size} shipping methods"

      records.each do |record|
        ActiveRecord::Base.transaction { import(record) }
      rescue => error
        @result.failures << { name: record["name"], error: error.message }
        say "  FAILED  #{record['name']}  #{error.message}"
      end

      say "done: #{@result}"
      @result
    end

    private

    def import(record)
      name = record["name"]
      method = Spree::ShippingMethod.find_or_initialize_by(name: name)
      new_record = method.new_record?

      method.code = record["sku"]
      method.available_to_all = true
      method.shipping_categories = [default_shipping_category]
      # Flat rate per order, matching what B2BWave charged.
      method.calculator ||= Spree::Calculator::Shipping::FlatRate.new
      method.save!

      method.calculator.set_preference(:amount, BigDecimal(record["price"].to_s))
      method.calculator.set_preference(:currency, Spree::Config.currency)
      method.calculator.save!

      # Restrict to the zones the store actually ships to. North America is the
      # seeded zone containing the US; without a zone Solidus offers no rates.
      method.zones = [north_america].compact if method.zones.empty?
      method.save!

      new_record ? @result.created += 1 : @result.updated += 1
    end

    def default_shipping_category
      @default_shipping_category ||= Spree::ShippingCategory.find_or_create_by!(name: "Default")
    end

    def north_america
      @north_america ||= Spree::Zone.find_by(name: "North America")
    end

    def say(message)
      @logger.info("[shipping-import] #{message}")
      puts message if $stdout.tty? || Rails.env.development?
    end
  end
end
