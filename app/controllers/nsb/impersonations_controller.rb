# frozen_string_literal: true

module Nsb
  # Stops an admin's phone-in order impersonation. Deliberately a plain
  # ApplicationController rather than Spree::Admin::BaseController: while
  # impersonating, spree_current_user is the customer, so /admin's own
  # authorization (built from spree_current_user) is unreachable. This has to
  # be reachable from the storefront -- it's what the impersonation bar's
  # "Stop" button hits -- so authorization here is checked against
  # true_spree_user, the real signed-in admin, not spree_current_user.
  class ImpersonationsController < ApplicationController
    before_action :require_true_admin

    def destroy
      if impersonating_spree_user?
        Rails.logger.info(
          "[impersonation] admin=#{true_spree_user.email} (##{true_spree_user.id}) " \
          "stopped acting as user=#{spree_current_user.email} (##{spree_current_user.id})"
        )
      end

      stop_impersonating_spree_user
      redirect_to root_path
    end

    private

    def require_true_admin
      redirect_to root_path unless true_spree_user.try(:has_spree_role?, "admin")
    end
  end
end
