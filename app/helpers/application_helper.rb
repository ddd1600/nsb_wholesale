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

end
