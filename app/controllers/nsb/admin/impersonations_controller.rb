# frozen_string_literal: true

module Nsb
  module Admin
    # Starts an admin placing a phone-in order on behalf of a wholesale
    # customer. Inherits Spree::Admin::BaseController for its authentication --
    # this only runs while the admin is still, in fact, the admin (see
    # Nsb::ImpersonationsController for why stopping can't live here too).
    class ImpersonationsController < Spree::Admin::BaseController
      def create
        user = Spree.user_class.find_by(id: params[:user_id])

        if user.nil?
          flash[:error] = "Couldn't find that customer."
        elsif user.has_spree_role?("admin")
          flash[:error] = "Can't place an order on behalf of an admin account."
        else
          impersonate_spree_user(user)
          Rails.logger.info(
            "[impersonation] admin=#{true_spree_user.email} (##{true_spree_user.id}) " \
            "started acting as user=#{user.email} (##{user.id})"
          )
          flash[:success] = "You're now placing an order for #{user.email}."
        end

        redirect_to root_path
      end
    end
  end
end
