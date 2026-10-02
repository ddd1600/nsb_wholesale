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

  # The few products previewed under each sub-category heading, most-ordered
  # first. Solidus's taxon_preview takes the first four the database returns;
  # this asks it for all of them, ranks them, then keeps four.
  def ranked_taxon_preview(taxon, max = 4)
    Nsb::SortsProductsByDemand.sort(taxon_preview(taxon, 1_000).to_a).first(max)
  end

end
