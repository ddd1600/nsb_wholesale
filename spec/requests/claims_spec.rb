# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

RSpec.describe "Account claim", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:company) { "14 Carrot Whole Foods" }

  # Emails build their links from the default store's url.
  let!(:store) { create(:store, default: true, url: "wholesale.example.com") }

  let!(:customer) do
    create(:user, email: "buyer@example.com").tap do |user|
      user.update!(
        b2b_customer_id: 5001,
        admin_metadata: { "b2bwave" => { "company_name" => company } }
      )
    end
  end

  # The mail goes out with deliver_later, and the suite runs ActiveJob on the
  # :test adapter, so jobs are enqueued rather than run. Draining the queue here
  # keeps these examples asserting on real delivered mail.
  def claim(email)
    perform_enqueued_jobs do
      post create_claim_path, params: { claim: { email: email } }
    end
  end

  describe "GET /claim" do
    it "renders the form" do
      get claim_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /claim with a known address" do
    it "sends exactly one claim email to that address" do
      expect { claim("buyer@example.com") }
        .to change { ActionMailer::Base.deliveries.size }.by(1)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq(["buyer@example.com"])
      expect(mail.body.to_s).to include(company)
    end

    it "redirects to the confirmation page" do
      claim("buyer@example.com")
      expect(response).to redirect_to(claim_sent_path(email: "buyer@example.com"))
    end

    it "matches regardless of the case the customer types" do
      expect { claim("BUYER@Example.COM") }
        .to change { ActionMailer::Base.deliveries.size }.by(1)
    end

    it "stores only a digest of the token, never the token itself" do
      claim("buyer@example.com")

      stored = customer.reload.reset_password_token
      raw = ActionMailer::Base.deliveries.last.body.to_s[/reset_password_token=([^\s&"]+)/, 1]
      expect(stored).to be_present
      expect(raw).to be_present
      expect(stored).not_to eq(raw)
    end

    it "does not sign anyone in merely by requesting a link" do
      claim("buyer@example.com")
      get account_path
      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "POST /claim with an unknown address" do
    it "tells the visitor the address is not on file" do
      claim("nobody@example.com")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("nobody@example.com")
      expect(flash.now[:error]).to include("don't have")
    end

    it "sends no email" do
      expect { claim("nobody@example.com") }
        .not_to change { ActionMailer::Base.deliveries.size }
    end

    it "rejects a blank submission without touching the mailer" do
      expect { claim("") }.not_to change { ActionMailer::Base.deliveries.size }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "following the emailed link" do
    it "greets the customer by company name" do
      token = customer.send_claim_instructions

      get edit_spree_user_password_path(reset_password_token: token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(company)
    end

    it "lets the customer set a password and signs them in" do
      token = customer.send_claim_instructions

      put update_password_path, params: {
        spree_user: {
          reset_password_token: token,
          password: "correct horse battery",
          password_confirmation: "correct horse battery"
        }
      }

      expect(customer.reload.valid_password?("correct horse battery")).to be(true)
      # sign_in_after_reset_password is on, so they land signed in.
      get account_path
      expect(response).to have_http_status(:ok)
    end

    it "refuses a token that was never issued" do
      put update_password_path, params: {
        spree_user: {
          reset_password_token: "not-a-real-token",
          password: "correct horse battery",
          password_confirmation: "correct horse battery"
        }
      }

      expect(customer.reload.valid_password?("correct horse battery")).to be(false)
    end

    it "refuses an expired token" do
      token = customer.send_claim_instructions
      travel_to (Devise.reset_password_within + 1.hour).from_now do
        put update_password_path, params: {
          spree_user: {
            reset_password_token: token,
            password: "correct horse battery",
            password_confirmation: "correct horse battery"
          }
        }
      end

      expect(customer.reload.valid_password?("correct horse battery")).to be(false)
    end

    it "cannot be replayed after the password is set" do
      token = customer.send_claim_instructions
      params = {
        spree_user: {
          reset_password_token: token,
          password: "first password here",
          password_confirmation: "first password here"
        }
      }
      put update_password_path, params: params

      # Same token again, trying to set a different password.
      put update_password_path, params: {
        spree_user: params[:spree_user].merge(
          password: "attacker password", password_confirmation: "attacker password"
        )
      }

      expect(customer.reload.valid_password?("attacker password")).to be(false)
      expect(customer.valid_password?("first password here")).to be(true)
    end
  end
end
