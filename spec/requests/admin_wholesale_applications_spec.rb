# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# The operator's side of the flow. These are thin, but they are the only thing
# standing between a broken admin template and finding out about it in
# production -- the views use Solidus admin helpers this app does not otherwise
# touch.
RSpec.describe "Admin wholesale applications", type: :request do
  let(:admin) { create(:admin_user) }

  let!(:application) do
    Nsb::WholesaleApplication.create!(
      business_name: "Coastal Apothecary", contact_name: "Jo Rivera",
      email: "jo@coastalapothecary.test", phone: "843-555-0134",
      address: "12 Front Street", retail_license_state: "SC",
      retail_license_number: "RL-99881", sells: "Supplements",
      interested_in: "Tinctures", heard_about_us: "A rep"
    )
  end

  context "when signed in as an admin" do
    before { sign_in admin }

    it "lists pending applications" do
      get "/admin/wholesale_applications"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Coastal Apothecary")
    end

    it "shows everything the operator needs to judge the application" do
      get "/admin/wholesale_applications/#{application.id}"

      expect(response).to have_http_status(:ok)
      # The phone is stored formatted, however it was typed, so the operator
      # reading a list of applications is not also parsing three phone formats.
      expect(response.body).to include("RL-99881", "jo@coastalapothecary.test", "(843) 555-0134")
    end

    it "approves, creating the account and emailing them" do
      expect { post "/admin/wholesale_applications/#{application.id}/approve" }
        .to change(Spree::User, :count).by(1)
        .and have_enqueued_mail(Nsb::ApprovalMailer, :approved)

      expect(application.reload).to be_approved
    end

    it "declines without emailing the applicant" do
      expect { post "/admin/wholesale_applications/#{application.id}/decline" }
        .not_to change(Spree::User, :count)

      expect(application.reload).to be_declined
    end
  end

  # The whole review surface sits behind Solidus's admin authentication, which
  # is the reason the controller inherits from Spree::Admin::BaseController
  # rather than this app's ApplicationController.
  context "when not an admin" do
    it "does not let a signed-out visitor see applications" do
      get "/admin/wholesale_applications"

      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to include("Coastal Apothecary")
    end

    it "does not let an ordinary customer see them" do
      sign_in create(:user)

      get "/admin/wholesale_applications"

      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to include("Coastal Apothecary")
    end
  end
end
