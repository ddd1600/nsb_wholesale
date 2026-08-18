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

    it "lets the correct password through" do
      get "/", headers: basic_auth("biscuits")
      expect(response).to have_http_status(:ok)
    end

    it "accepts any username, since only the password is checked" do
      get "/", headers: basic_auth("biscuits", user: "whoever")
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
      get "/"
      expect(response).to have_http_status(:ok)
    end
  end
end
