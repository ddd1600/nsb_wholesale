# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

RSpec.describe Nsb::CustomerDirectory do
  let!(:store) { create(:store) }

  def b2bwave_customer(company, last_order: nil)
    create(:user, admin_metadata: {
      "b2bwave" => { "company_name" => company, "latest_order_submitted_at" => last_order }.compact
    })
  end

  it "puts the most recent order first, then never-ordered customers A-Z" do
    old = b2bwave_customer("Old Shop", last_order: "01/15/2024 09:00")
    recent = b2bwave_customer("Recent Shop", last_order: "07/31/2026 11:13")
    zed = b2bwave_customer("Zed Never")
    abe = b2bwave_customer("Abe Never")

    expect(described_class.new.entries.map(&:user)).to eq([ recent, old, abe, zed ])
  end

  it "counts a portal order when it is newer than the B2BWave one" do
    customer = b2bwave_customer("Moved Over", last_order: "01/15/2024 09:00")
    create(:completed_order_with_totals, user: customer, store: store).update_column(:completed_at, Time.zone.parse("2026-10-01"))

    entry = described_class.new.entries.first

    expect(entry.last_order_on).to eq(Date.new(2026, 10, 1))
    expect(entry.last_order_source).to eq(:portal)
  end

  it "leaves out admin accounts" do
    create(:admin_user)

    expect(described_class.new.entries).to be_empty
  end

  it "falls back to a saved address's company, then the email, for the business name" do
    with_address = create(:user)
    with_address.update!(bill_address: create(:address, company: "Address Co"))
    bare = create(:user, email: "bare@example.com")

    names = described_class.new.entries.to_h { |e| [ e.user, e.business_name ] }

    expect(names[with_address]).to eq("Address Co")
    expect(names[bare]).to eq("bare@example.com")
  end

  it "matches ignoring case, punctuation, '2' for 'to' and '&' for 'and'" do
    b2bwave_customer("Back To Nature")
    b2bwave_customer("Smoke & Vapor")

    expect(described_class.new(query: "back 2 nature").entries.map(&:business_name)).to eq([ "Back To Nature" ])
    expect(described_class.new(query: "BACKTONATURE").entries.map(&:business_name)).to eq([ "Back To Nature" ])
    expect(described_class.new(query: "smoke and vapor").entries.map(&:business_name)).to eq([ "Smoke & Vapor" ])
  end
end
