# frozen_string_literal: true

module Nsb
  # Lets the admin user form save "Can pay by check (Net 14)" (Nsb::CheckTerms).
  #
  # Admin users controller only, never Spree::PermittedAttributes.user_attributes
  # -- that list is also what the storefront account page permits, which would
  # let any customer give themselves net terms. Same reasoning as
  # Nsb::AdminUserMinimumOrderParams.
  #
  # Prepended onto Spree::Admin::UsersController in
  # config/initializers/solidus_decorators.rb.
  module AdminUserCheckTermsParams
    private

    def user_params
      permitted = super
      if params[:user]&.key?(:nsb_pays_by_check)
        permitted[:nsb_pays_by_check] = ActiveModel::Type::Boolean.new.cast(params[:user][:nsb_pays_by_check])
      end
      permitted
    end
  end
end
