# frozen_string_literal: true

module Nsb
  # Solidus seeds a single refund reason, "Return processing", which tells the
  # operator nothing six months later when reconciling against Square.
  #
  # These are the reasons a wholesale CBD order actually gets money back, in
  # rough order of frequency. "Other" is last and exists so the operator is never
  # forced to file a refund under a reason that isn't true -- it pairs with the
  # free-text note added by the admin form override.
  #
  # Safe to re-run: matched on name, and existing reasons are left active.
  class RefundReasonSeeder
    REASONS = [
      "Damaged in transit",
      "Wrong item shipped",
      "Item out of stock",
      "Order cancelled by customer",
      "Duplicate charge",
      "Pricing correction",
      "Goodwill / customer service",
      "Other"
    ].freeze

    def call
      created = 0
      REASONS.each do |name|
        reason = Spree::RefundReason.find_or_initialize_by(name: name)
        next unless reason.new_record?

        reason.active = true
        reason.mutable = true
        reason.save!
        created += 1
      end

      puts "refund reasons: #{created} added, #{Spree::RefundReason.count} total"
      Spree::RefundReason.order(:name).pluck(:name)
    end
  end
end
