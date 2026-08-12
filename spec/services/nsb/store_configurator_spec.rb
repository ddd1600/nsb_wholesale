# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

RSpec.describe Nsb::StoreConfigurator do
  let!(:store) do
    create(:store, default: true, name: "Sample Store", url: "example.com",
                   mail_from_address: "store@example.com", code: "sample-store")
  end

  it "replaces the seeded placeholder identity" do
    described_class.new(env: {}).call

    store.reload
    expect(store.name).to eq("New South Botanicals Wholesale")
    expect(store.url).to eq("wholesale.newsouthbotanicals.com")
    expect(store.mail_from_address).to eq("connect@newsouthbotanicals.com")
  end

  it "prefers environment values so Render can correct them without a deploy" do
    described_class.new(env: {
      "STORE_NAME" => "NSB Trade",
      "STORE_URL" => "orders.example.org",
      "STORE_MAIL_FROM" => "sales@example.org"
    }).call

    store.reload
    expect(store.name).to eq("NSB Trade")
    expect(store.url).to eq("orders.example.org")
    expect(store.mail_from_address).to eq("sales@example.org")
  end

  it "is safe to re-run" do
    described_class.new(env: {}).call
    expect { described_class.new(env: {}).call }.not_to change { store.reload.updated_at }
  end

  it "leaves a code the operator has already customised" do
    store.update!(code: "chosen-by-hand")

    described_class.new(env: {}).call

    expect(store.reload.code).to eq("chosen-by-hand")
  end
end
