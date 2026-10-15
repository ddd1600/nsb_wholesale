class ApplicationController < ActionController::Base
  # Lets an admin act as a wholesale customer to place phone-in orders on
  # their behalf. `spree_current_user` (solidus_auth_devise) delegates to
  # Devise's `current_spree_user`, which is exactly what pretender overrides
  # -- so this one line is enough for cart, checkout and order association to
  # pick up the impersonated customer everywhere, with no changes to Solidus's
  # own controllers. `true_spree_user` always stays the real, authenticated
  # admin.
  #
  # The default resource lookup is overridden because pretender's own default
  # (`scope.to_s.classify.constantize`) would try to constantize "SpreeUser",
  # which doesn't exist -- the actual class is `Spree.user_class`.
  impersonates :spree_user, with: ->(id) { Spree.user_class.find_by(id: id) }

  # Not provided by pretender itself (it only defines current/true/impersonate/
  # stop_impersonating). Kept here, next to `impersonates`, rather than
  # scattered across the controllers that need it.
  def impersonating_spree_user?
    true_spree_user.present? && true_spree_user != spree_current_user
  end
  helper_method :impersonating_spree_user?
end
