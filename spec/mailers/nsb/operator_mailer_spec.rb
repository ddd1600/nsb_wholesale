# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

RSpec.describe Nsb::OperatorMailer do
  describe ".recipients" do
    around do |example|
      original = ENV["OPERATOR_NOTIFICATION_EMAILS"]
      example.run
    ensure
      ENV["OPERATOR_NOTIFICATION_EMAILS"] = original
    end

    it "uses the defaults when the env var is unset" do
      ENV.delete("OPERATOR_NOTIFICATION_EMAILS")
      expect(described_class.recipients).to eq(%w[david@newsouthbotanicals.com ddd1600@gmail.com])
    end

    it "keeps ddd1600@gmail.com when the env var lists other people" do
      ENV["OPERATOR_NOTIFICATION_EMAILS"] = "someone@example.com, other@example.com"
      expect(described_class.recipients)
        .to eq(%w[someone@example.com other@example.com ddd1600@gmail.com])
    end

    it "does not list ddd1600@gmail.com twice" do
      ENV["OPERATOR_NOTIFICATION_EMAILS"] = "DDD1600@gmail.com,someone@example.com"
      expect(described_class.recipients).to eq(%w[DDD1600@gmail.com someone@example.com])
    end
  end

  describe "#application_received" do
    it "is addressed to the operator recipients" do
      ENV.delete("OPERATOR_NOTIFICATION_EMAILS")
      create(:store, url: "wholesale.example.com")
      application = Nsb::WholesaleApplication.new(id: 1, business_name: "Test Shop")
      mail = described_class.application_received(application)
      expect(mail.to).to include("ddd1600@gmail.com")
      expect(mail.subject).to eq("Wholesale application: Test Shop")
    end
  end
end
