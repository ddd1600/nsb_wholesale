# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# The path for a business that is not a customer yet: apply, wait, and be let in
# by hand. Nothing here creates an account -- approval does, which is the point.
RSpec.describe "Wholesale applications", type: :request do
  let(:valid_params) do
    {
      wholesale_application: {
        business_name: "Coastal Apothecary",
        contact_name: "Jo Rivera",
        email: "jo@coastalapothecary.test",
        phone: "843-555-0134",
        address: "12 Front Street, Georgetown, SC 29440",
        retail_license_state: "SC",
        retail_license_number: "RL-99881",
        sells: "Herbal supplements and wellness goods",
        interested_in: "Tinctures and gummies",
        heard_about_us: "A rep visited our shop"
      }
    }
  end

  describe "submitting the form" do
    it "records the application and tells the applicant it arrived" do
      expect { post "/apply", params: valid_params }
        .to change(Nsb::WholesaleApplication, :count).by(1)

      expect(response).to redirect_to(application_received_path)
      expect(Nsb::WholesaleApplication.last).to be_pending
    end

    # The operator would otherwise have to go looking; this portal is
    # deliberately hands-off.
    it "emails the operator" do
      expect { post "/apply", params: valid_params }
        .to have_enqueued_mail(Nsb::OperatorMailer, :application_received)
    end

    it "creates no account -- approval does that" do
      expect { post "/apply", params: valid_params }.not_to change(Spree::User, :count)
    end

    it "re-renders with errors when a required field is missing" do
      valid_params[:wholesale_application][:retail_license_number] = ""

      expect { post "/apply", params: valid_params }.not_to change(Nsb::WholesaleApplication, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # 360 migrated accounts make this likely, and a duplicate is work for the
  # operator to reconcile rather than a harmless extra row.
  describe "when the applicant already has an account" do
    before { create(:user, email: "jo@coastalapothecary.test") }

    it "points them at the claim flow instead of taking an application" do
      expect { post "/apply", params: valid_params }.not_to change(Nsb::WholesaleApplication, :count)

      expect(response.body).to include(claim_path(email: "jo@coastalapothecary.test"))
    end
  end

  describe "when an application from the same address is already pending" do
    it "is rejected rather than queued twice" do
      post "/apply", params: valid_params

      expect { post "/apply", params: valid_params }
        .not_to change(Nsb::WholesaleApplication, :count)
    end
  end
end

RSpec.describe Nsb::WholesaleApplication do
  subject(:application) do
    described_class.create!(
      business_name: "Coastal Apothecary", contact_name: "Jo Rivera",
      email: "jo@coastalapothecary.test", phone: "843-555-0134",
      address: "12 Front Street", retail_license_state: "sc",
      retail_license_number: "RL-99881", sells: "Supplements",
      interested_in: "Tinctures", heard_about_us: "A rep"
    )
  end

  it "normalizes the email and license state, because people type them how they like" do
    expect(application.email).to eq("jo@coastalapothecary.test")
    expect(application.retail_license_state).to eq("SC")
  end

  describe "#approve!" do
    it "creates the account the applicant will claim" do
      expect { application.approve! }.to change(Spree::User, :count).by(1)

      expect(application.reload).to be_approved
      expect(application.user.email).to eq("jo@coastalapothecary.test")
      expect(application.reviewed_at).to be_present
    end

    it "emails the applicant a link to set a password" do
      expect { application.approve! }
        .to have_enqueued_mail(Nsb::ApprovalMailer, :approved)
    end

    # The link in that email is a Devise reset token, the same mechanism the
    # migrated customers' claim flow uses.
    it "leaves the account with a usable reset token" do
      application.approve!

      expect(application.user.reset_password_token).to be_present
    end

    it "refuses to approve the same application twice" do
      application.approve!

      expect { application.approve! }.to raise_error(ArgumentError, /already approved/)
    end
  end

  describe "#decline!" do
    # Silent at the operator's request: it clears the pending list and the
    # applicant hears nothing.
    it "marks it reviewed and sends the applicant nothing" do
      expect { application.decline! }.not_to have_enqueued_mail(Nsb::ApprovalMailer, :approved)

      expect(application.reload).to be_declined
      expect(application.reviewed_at).to be_present
    end

    it "creates no account" do
      expect { application.decline! }.not_to change(Spree::User, :count)
    end
  end
end

# The other half of the operator's visibility: 360 accounts are waiting to be
# claimed, and they want to know as each one comes to life.
RSpec.describe "Activation notification", type: :request do
  let(:customer) { create(:user, email: "returning@example.test") }

  def set_password_with(token)
    put "/password/change", params: {
      spree_user: {
        reset_password_token: token,
        password: "NewPassword123!",
        password_confirmation: "NewPassword123!"
      }
    }
  end

  it "emails the operator the first time a migrated customer sets a password" do
    token = customer.send_claim_instructions

    expect { set_password_with(token) }
      .to have_enqueued_mail(Nsb::OperatorMailer, :customer_activated)

    expect(customer.reload.nsb_activated_at).to be_present
  end

  # A customer who forgets their password later is not activating again, and an
  # email saying they did would be wrong twice over.
  it "does not email again on a later password reset" do
    set_password_with(customer.send_claim_instructions)
    customer.reload

    expect { set_password_with(customer.send_claim_instructions) }
      .not_to have_enqueued_mail(Nsb::OperatorMailer, :customer_activated)
  end
end
