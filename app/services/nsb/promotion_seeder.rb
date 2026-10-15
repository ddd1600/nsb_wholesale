# frozen_string_literal: true

module Nsb
  # Creates the portal's two standing promotions, using Solidus's own promotion
  # system (solidus_legacy_promotions) so both appear and can be edited, paused
  # or expired in the admin under Promotions.
  #
  #   NEWPORTAL         20% off the merchandise subtotal, once per account.
  #                     Codes are case-insensitive: Solidus stores them
  #                     lowercased and lowercases what the customer types.
  #                     The OneUsePerUser rule counts only COMPLETED orders,
  #                     so a customer who applies it and abandons the cart has
  #                     not used it up.
  #
  #   Free shipping     Applied automatically, no code, when the merchandise
  #                     subtotal is $500 or more (operator "gte", i.e. >=, so
  #                     exactly $500 qualifies). Zeroes every shipment's cost.
  #
  # Both measure item_total: before discounts and shipping. So a $500 cart
  # still ships free after NEWPORTAL's 20% -- the same figure the minimum order
  # (Nsb::MinimumOrder) is measured against.
  #
  # Safe to re-run. Matched on name, and an existing promotion is left exactly
  # as it is: once the operator has changed the percentage or threshold in the
  # admin, re-running this must not quietly put it back.
  class PromotionSeeder
    NEWPORTAL_NAME = "NEWPORTAL - 20% off, once per account"
    NEWPORTAL_CODE = "newportal"
    NEWPORTAL_PERCENT = 20

    FREE_SHIPPING_NAME = "Free shipping on orders of $500 or more"
    FREE_SHIPPING_THRESHOLD = 500

    def initialize(logger: Rails.logger)
      @logger = logger
    end

    def call
      [ seed_newportal, seed_free_shipping ]
    end

    private

    def seed_newportal
      existing = Spree::Promotion.find_by(name: NEWPORTAL_NAME)
      return report(existing, "already exists, left unchanged") if existing

      promotion = Spree::Promotion.transaction do
        Spree::Promotion.create!(
          name: NEWPORTAL_NAME,
          description: "Welcome to the new portal: #{NEWPORTAL_PERCENT}% off one order per account.",
          apply_automatically: false
        ).tap do |promo|
          promo.codes.create!(value: NEWPORTAL_CODE)
          promo.rules << Spree::Promotion::Rules::OneUsePerUser.new
          promo.actions << Spree::Promotion::Actions::CreateAdjustment.new(
            calculator: Spree::Calculator::FlatPercentItemTotal.new(preferred_flat_percent: NEWPORTAL_PERCENT)
          )
          promo.save!
        end
      end
      report(promotion, "created")
    end

    def seed_free_shipping
      existing = Spree::Promotion.find_by(name: FREE_SHIPPING_NAME)
      return report(existing, "already exists, left unchanged") if existing

      promotion = Spree::Promotion.transaction do
        Spree::Promotion.create!(
          name: FREE_SHIPPING_NAME,
          description: "Shipping is free when the order subtotal is $#{FREE_SHIPPING_THRESHOLD} or more.",
          apply_automatically: true
        ).tap do |promo|
          promo.rules << Spree::Promotion::Rules::ItemTotal.new(
            preferred_amount: FREE_SHIPPING_THRESHOLD,
            preferred_operator: "gte"
          )
          promo.actions << Spree::Promotion::Actions::FreeShipping.new
          promo.save!
        end
      end
      report(promotion, "created")
    end

    def report(promotion, what)
      message = "#{promotion.name}: #{what}"
      @logger.info("[promotions] #{message}")
      puts message if $stdout.tty? || Rails.env.development?
      promotion
    end
  end
end
