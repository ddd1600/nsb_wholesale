# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# The gate is Rack middleware, so it is exercised here through real requests
# rather than by unit-testing the class. What matters is what it lets through.
RSpec.describe "Site password gate", type: :request do
  around do |example|
    original = ENV["SITE_PASSWORD"]
    ENV["SITE_PASSWORD"] = password
    example.run
    ENV["SITE_PASSWORD"] = original
  end

  def basic_auth(pass, user: "anyone")
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(user, pass) }
  end

  context "when SITE_PASSWORD is set" do
    let(:password) { "biscuits" }

    it "blocks the storefront" do
      get "/"
      expect(response).to have_http_status(:unauthorized)
    end

    it "blocks the admin, which does not use this app's ApplicationController" do
      get "/admin/login"
      expect(response).to have_http_status(:unauthorized)
    end

    it "blocks the account claim page" do
      get "/claim"
      expect(response).to have_http_status(:unauthorized)
    end

    # Square is a machine with no password to give. Gating it would answer 401,
    # Square would retry a few times and stop, and refunds issued while the site
    # is still private would never reconcile -- silently. Safe to leave open:
    # that endpoint authenticates every request by HMAC signature and does
    # nothing without a valid one, which spec/requests/square_webhooks_spec.rb
    # covers.
    # The endpoint answers 401 here too, because no signature key is set in this
    # context -- so the assertion is about WHO answered. The gate challenges with
    # WWW-Authenticate; the controller just refuses. Their absence is what says
    # the request reached the app.
    it "lets Square's webhook past the gate, to be judged on its signature" do
      post "/square/webhooks", params: "{}", headers: { "CONTENT_TYPE" => "application/json" }

      expect(response.headers["WWW-Authenticate"]).to be_nil
    end

    it "still challenges a normal page, for contrast" do
      get "/welcome"

      expect(response.headers["WWW-Authenticate"]).to be_present
    end

    # /welcome rather than "/": root now redirects a signed-out visitor to the
    # welcome page, so a 200 there would be testing the wrong thing. What is
    # being asserted is that the middleware did not answer the request itself.
    it "lets the correct password through" do
      get "/welcome", headers: basic_auth("biscuits")
      expect(response).to have_http_status(:ok)
    end

    it "accepts any username, since only the password is checked" do
      get "/welcome", headers: basic_auth("biscuits", user: "whoever")
      expect(response).to have_http_status(:ok)
    end

    it "rejects a wrong password" do
      get "/", headers: basic_auth("crumpets")
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects an empty password" do
      get "/", headers: basic_auth("")
      expect(response).to have_http_status(:unauthorized)
    end

    # Render polls /up to decide whether the service is healthy. Gating it would
    # make every deploy look like a failure and take the site down.
    it "leaves the health check open" do
      get "/up"
      expect(response).to have_http_status(:ok)
    end

    it "prompts the browser for credentials rather than just erroring" do
      get "/"
      expect(response.headers["WWW-Authenticate"]).to match(/^Basic realm=/)
    end
  end

  context "when SITE_PASSWORD is not set" do
    let(:password) { nil }

    it "does not gate anything, so development and test are unaffected" do
      get "/welcome"
      expect(response).to have_http_status(:ok)
    end
  end
end
