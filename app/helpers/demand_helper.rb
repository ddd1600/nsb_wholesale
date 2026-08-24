# frozen_string_literal: true

# Formatting for the homepage demand ranking (Nsb::OrderFrequencyRanking).
module DemandHelper
  # Anything below this would print as "0.0%", which reads as "none" when it
  # actually means "a little". Say so instead.
  SMALLEST_SHOWN_SHARE = 0.001

  # A product's share of total demand. Sub-1% shares get a decimal place, since
  # most of this catalog's long tail lives between 0.1% and 1%.
  def demand_share(share)
    return "<0.1%" if share.positive? && share < SMALLEST_SHOWN_SHARE

    # A decimal place only where it adds something -- not on a flat zero.
    precision = share.positive? && share < 0.01 ? 1 : 0
    number_to_percentage(share * 100, precision: precision)
  end
end
