# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"
require Rails.root.join("config/mail_delivery")

RSpec.describe MailDelivery::TokenInterceptor do
  let(:message) { instance_double(Mail::Message, delivery_method: delivery_method) }

  context "with an XOAUTH2 SMTP delivery method" do
    let(:settings) { { authentication: :xoauth2, password: nil } }
    let(:delivery_method) { instance_double(Mail::SMTP, settings: settings) }

    it "injects a fresh access token as the SMTP password" do
      allow(Nsb::GmailOauthToken).to receive(:access_token).and_return("ya29.fresh")

      described_class.delivering_email(message)

      expect(settings[:password]).to eq("ya29.fresh")
    end

    it "asks for the token on every delivery, so a stale one is never reused" do
      allow(Nsb::GmailOauthToken).to receive(:access_token).and_return("ya29.a", "ya29.b")

      described_class.delivering_email(message)
      described_class.delivering_email(message)

      expect(settings[:password]).to eq("ya29.b")
    end
  end

  context "with a non-SMTP delivery method" do
    # letter_opener in development, and :test in specs.
    let(:delivery_method) { instance_double(Mail::TestMailer) }

    it "does nothing and does not fetch a token" do
      allow(delivery_method).to receive(:respond_to?).with(:settings).and_return(false)
      allow(Nsb::GmailOauthToken).to receive(:access_token)

      expect { described_class.delivering_email(message) }.not_to raise_error
      expect(Nsb::GmailOauthToken).not_to have_received(:access_token)
    end
  end

  context "with SMTP configured for password auth" do
    let(:settings) { { authentication: :plain, password: "unchanged" } }
    let(:delivery_method) { instance_double(Mail::SMTP, settings: settings) }

    it "leaves the settings alone" do
      allow(Nsb::GmailOauthToken).to receive(:access_token)

      described_class.delivering_email(message)

      expect(settings[:password]).to eq("unchanged")
      expect(Nsb::GmailOauthToken).not_to have_received(:access_token)
    end
  end
end
