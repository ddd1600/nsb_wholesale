# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

RSpec.describe Nsb::UsStates do
  before { described_class.reset! }
  after { described_class.reset! }

  it "offers every state, alphabetically" do
    expect(described_class.options.first).to eq([ "Alabama", "AL" ])
    expect(described_class.options.size).to be > 50
  end

  it "includes territories, which have licensed retailers too" do
    expect(described_class.codes).to include("PR", "VI", "DC")
  end

  it "excludes APO/FPO military codes, which are not licensing jurisdictions" do
    expect(described_class.codes).not_to include("AA", "AE", "AP")
  end

  it "does not depend on Spree::State rows" do
    # A validation that read the database would fail closed on an unseeded one
    # and reject every application. This is the regression that caused.
    allow(Spree::Country).to receive(:find_by).and_return(nil)

    expect(described_class.codes).to include("SC")
  end
end
