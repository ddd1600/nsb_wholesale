# frozen_string_literal: true

module Nsb
  module Admin
    # Review and approval, inside Solidus's admin.
    #
    # Inherits Spree::Admin::BaseController for its authentication and its layout
    # -- this is the operator's existing admin session, not a second login.
    class WholesaleApplicationsController < Spree::Admin::BaseController
      def index
        @pending = Nsb::WholesaleApplication.pending.newest_first
        @reviewed = Nsb::WholesaleApplication.reviewed.newest_first.limit(50)
      end

      def show
        @application = Nsb::WholesaleApplication.find(params[:id])
      end

      def approve
        application = Nsb::WholesaleApplication.find(params[:id])
        application.approve!
        flash[:success] = "Approved #{application.business_name}. They've been emailed a link to set a password."
        redirect_to admin_wholesale_applications_path
      rescue ArgumentError => error
        flash[:error] = error.message
        redirect_to admin_wholesale_applications_path
      end

      def decline
        application = Nsb::WholesaleApplication.find(params[:id])
        application.decline!
        # Silent by the operator's choice: nothing is sent to the applicant.
        flash[:success] = "Declined #{application.business_name}. Nothing was sent to them."
        redirect_to admin_wholesale_applications_path
      rescue ArgumentError => error
        flash[:error] = error.message
        redirect_to admin_wholesale_applications_path
      end
    end
  end
end
