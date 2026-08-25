# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# A domain cutover is a few minutes of the app disagreeing with itself about
# where it lives. Nothing raises when that happens -- customers just get emailed
# links to a host that may not resolve yet. This reports the disagreement.
RSpec.describe Nsb::DomainStatus do
  subject(:status) { described_class.new(env: env) }

  let(:env) { {} }

  def set_app_host(host)
    allow(Rails.application.config.action_mailer).to receive(:default_url_options)
      .and_return({ host: host, protocol: "https" })
  end

  # Spree::Store.default returns an unsaved record when no store exists, which
  # is the state of a fresh test database. Create a real one instead of trying
  # to update that.
  def set_store_url(url)
    create(:store, default: true, url: url)
  end

  describe "reading the two settings" do
    it "reports the mailer host and the Solidus store host" do
      set_app_host("wholesale.example.com")
      set_store_url("wholesale.example.com")

      expect(status.app_host).to eq("wholesale.example.com")
      expect(status.store_url).to eq("wholesale.example.com")
    end

    # Operators paste URLs out of a browser; the settings want bare hosts.
    it "compares a pasted URL and a bare host as the same thing" do
      set_app_host("wholesale.example.com")
      set_store_url("https://Wholesale.Example.com/")

      expect(status.store_url).to eq("wholesale.example.com")
      expect(status).to be_consistent
    end
  end

  describe "#consistent?" do
    it "is false when the two hosts disagree" do
      set_app_host("nsb-wholesale.onrender.com")
      set_store_url("wholesale.example.com")

      expect(status).not_to be_consistent
    end

    it "is false when the mailer host is missing entirely" do
      set_app_host(nil)
      set_store_url("wholesale.example.com")

      expect(status).not_to be_consistent
    end
  end

  describe "#cut_over?" do
    it "is false while both still point at the onrender.com fallback" do
      set_app_host("nsb-wholesale.onrender.com")
      set_store_url("nsb-wholesale.onrender.com")

      expect(status).to be_consistent
      expect(status).not_to be_cut_over
    end

    it "is true once both point at the custom domain" do
      set_app_host("wholesale.newsouthbotanicals.com")
      set_store_url("wholesale.newsouthbotanicals.com")

      expect(status).to be_cut_over
    end

    it "is false when they agree on nothing useful because they disagree" do
      set_app_host("wholesale.newsouthbotanicals.com")
      set_store_url("nsb-wholesale.onrender.com")

      expect(status).not_to be_cut_over
    end
  end

  describe "reporting where the values came from" do
    context "when the environment sets them" do
      let(:env) { { "APP_HOST" => "wholesale.example.com", "STORE_URL" => "wholesale.example.com" } }

      it "says so" do
        expect(status).to be_app_host_from_env
        expect(status).to be_store_url_from_env
      end
    end

    # This is the trap: unset does not mean "unconfigured", it means the code
    # defaults take over -- and those already name the wholesale subdomain.
    context "when the environment sets neither" do
      it "reports both as defaulted" do
        expect(status).not_to be_app_host_from_env
        expect(status).not_to be_store_url_from_env
      end
    end
  end
end
