module ApplicationHelper

  # Wholesale pricing is for customers, not the public.
  #
  # The catalog is browsable logged out -- a prospect deciding whether to apply
  # should be able to see what we sell -- but the prices are the commercially
  # sensitive part and a competitor should not be able to read our wholesale
  # sheet by visiting the site.
  #
  # Used at every point a price renders on an anonymous-reachable page. Guarded
  # in the views rather than by nilling out current_pricing_options, because that
  # object is also what the cart and checkout do their arithmetic with.
  def show_wholesale_prices?
    spree_current_user.present?
  end

  # The cheapest and dearest pack size of a product, as [min, max] Spree::Money.
  # A product with one price (or no variants) gives the same value twice. Nil
  # when prices are hidden from this visitor or none are set.
  #
  # Listings used to show only the master's price, so the THC Free Gummies read
  # "$12.50" when the 30ct is $30.00 (operator, 2026-10-15).
  def nsb_price_range(product)
    return unless show_wholesale_prices?

    variants = product.has_variants? ? product.variants : [ product.master ]
    prices = variants.filter_map { |variant| variant.price_for_options(current_pricing_options)&.money }
    prices.minmax_by(&:to_d) if prices.any?
  end

  # "$12.50 – $30.00", or a single "$20.00" when every pack costs the same.
  def nsb_price_range_html(range)
    return if range.nil?

    low, high = range
    low.to_d == high.to_d ? low.to_html : safe_join([ low.to_html, high.to_html ], " – ")
  end

  def nsb_display_price(product) = nsb_price_range_html(nsb_price_range(product))

  # The few products previewed under each sub-category heading, most-ordered
  # first. Solidus's taxon_preview takes the first four the database returns;
  # this asks it for all of them, ranks them, then keeps four.
  def ranked_taxon_preview(taxon, max = 4)
    Nsb::SortsProductsByDemand.sort(taxon_preview(taxon, 1_000).to_a).first(max)
  end

  # The minimum shown in the order-terms banner: the signed-in customer's own
  # if the admin set one, else the site-wide one. Mirrors
  # Nsb::MinimumOrder#nsb_minimum_order_amount, which is what checkout enforces.
  def nsb_display_minimum_order_amount
    customer_minimum = spree_current_user&.nsb_minimum_order_amount
    return customer_minimum unless customer_minimum.nil?

    current_store&.nsb_minimum_order_amount || 0
  end

  # The free-shipping threshold, read from the live promotion rather than
  # written into the view, so the banner follows whatever the operator sets in
  # admin -> Promotions and disappears if that promotion is paused or expired.
  # Nil when there is no active automatic free-shipping promotion.
  def nsb_free_shipping_threshold
    return @nsb_free_shipping_threshold if defined?(@nsb_free_shipping_threshold)

    rule = Spree::Promotion::Rules::ItemTotal
      .joins(promotion: :promotion_actions)
      .merge(Spree::Promotion.active.where(apply_automatically: true))
      .where(spree_promotion_actions: { type: "Spree::Promotion::Actions::FreeShipping" })
      .first
    @nsb_free_shipping_threshold = rule&.preferred_amount
  end

end
