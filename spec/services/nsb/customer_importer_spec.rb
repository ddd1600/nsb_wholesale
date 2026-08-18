# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

RSpec.describe Nsb::CustomerImporter do
  let(:data_file) { Pathname(Dir.mktmpdir) / "customers.json" }

  def write_customers(records)
    data_file.write(JSON.generate(records))
  end

  def record(overrides = {})
    {
      "b2b_customer_id" => 5001,
      "email" => "buyer@example.com",
      "company_name" => "Example Wholesale",
      "contact_name" => "Alex Buyer",
      "address" => nil,
      "source" => { "company_name" => "Example Wholesale", "tax_id" => "TX-1" }
    }.merge(overrides)
  end

  def address(overrides = {})
    {
      "address1" => "100 Main St",
      "address2" => nil,
      "city" => "Lexington",
      "zipcode" => "29072",
      "state" => "SC",
      "country_iso" => "US",
      "phone" => nil,
      "company" => "Example Wholesale",
      "name" => "Alex Buyer"
    }.merge(overrides)
  end

  after { FileUtils.remove_entry(data_file.dirname) }

  subject(:importer) { described_class.new(data_file: data_file) }

  it "creates a user keyed on b2b_customer_id" do
    write_customers([record])

    result = importer.call

    expect(result.created).to eq(1)
    expect(result.failures).to be_empty
    expect(Spree.user_class.find_by(b2b_customer_id: 5001).email).to eq("buyer@example.com")
  end

  describe "account security" do
    it "leaves no guessable password on an imported account" do
      write_customers([record])
      importer.call

      user = Spree.user_class.find_by(b2b_customer_id: 5001)
      expect(user.encrypted_password).to be_present
      ["", " ", "password", "buyer@example.com", "Example Wholesale", "123456"]
        .each { |guess| expect(user.valid_password?(guess)).to be(false) }
    end

    it "does not create a usable reset token at import time" do
      write_customers([record])
      importer.call

      # A token must only ever be minted by the customer's own claim request.
      expect(Spree.user_class.find_by(b2b_customer_id: 5001).reset_password_token).to be_nil
    end

    it "never overwrites the password of a customer who already claimed their account" do
      write_customers([record])
      importer.call
      user = Spree.user_class.find_by(b2b_customer_id: 5001)
      user.update!(password: "chosen-by-customer", password_confirmation: "chosen-by-customer")

      write_customers([record("company_name" => "Renamed Co")])
      described_class.new(data_file: data_file).call

      expect(user.reload.valid_password?("chosen-by-customer")).to be(true)
    end
  end

  describe "when a user with that email already exists" do
    # The operator's own admin account is created from ADMIN_EMAIL at seed time,
    # and he is also one of the 360 wholesale customers. This previously failed
    # with "Email has already been taken" partway through the import.
    let!(:existing) do
      create(:user, email: "buyer@example.com").tap do |user|
        user.update!(password: "already-chosen", password_confirmation: "already-chosen")
      end
    end

    it "attaches the B2BWave id to the existing account instead of duplicating" do
      write_customers([record])

      result = importer.call

      expect(result.failures).to be_empty
      expect(Spree.user_class.where(email: "buyer@example.com").count).to eq(1)
      expect(existing.reload.b2b_customer_id).to eq(5001)
    end

    it "does not disturb the password of the existing account" do
      write_customers([record])

      importer.call

      expect(existing.reload.valid_password?("already-chosen")).to be(true)
    end

    it "matches regardless of the case in the export" do
      write_customers([record("email" => "BUYER@Example.com")])

      importer.call

      expect(Spree.user_class.where(b2b_customer_id: 5001).count).to eq(1)
    end
  end

  it "updates in place rather than duplicating when re-run" do
    write_customers([record])
    importer.call

    write_customers([record("email" => "new@example.com")])
    result = described_class.new(data_file: data_file).call

    expect(result.created).to eq(0)
    expect(result.updated).to eq(1)
    expect(Spree.user_class.where(b2b_customer_id: 5001).count).to eq(1)
    expect(Spree.user_class.find_by(b2b_customer_id: 5001).email).to eq("new@example.com")
  end

  it "keeps the B2BWave record on the user for customers with no address" do
    write_customers([record])
    importer.call

    metadata = Spree.user_class.find_by(b2b_customer_id: 5001).admin_metadata
    expect(metadata.dig("b2bwave", "company_name")).to eq("Example Wholesale")
    expect(metadata.dig("b2bwave", "tax_id")).to eq("TX-1")
  end

  describe "addresses" do
    # The test database is built from schema.rb, so it has none of Solidus's
    # seeded countries or states. Create just the ones these examples need.
    let!(:usa) { create(:country, iso: "US", name: "United States of America") }
    let!(:south_carolina) { create(:state, country: usa, name: "South Carolina", abbr: "SC") }

    it "attaches a complete address as both bill and ship" do
      write_customers([record("address" => address)])

      result = importer.call

      expect(result.addresses).to eq(1)
      user = Spree.user_class.find_by(b2b_customer_id: 5001)
      expect(user.bill_address.city).to eq("Lexington")
      expect(user.bill_address.state.abbr).to eq("SC")
      expect(user.ship_address).to be_present
    end

    it "resolves a state given by full name as well as abbreviation" do
      write_customers([record("address" => address("state" => "South Carolina"))])

      importer.call

      expect(Spree.user_class.find_by(b2b_customer_id: 5001).bill_address.state.abbr).to eq("SC")
    end

    it "imports an address with no phone number" do
      # 339 of 360 exported customers have no phone; address_requires_phone is
      # disabled so these still import rather than being discarded.
      write_customers([record("address" => address("phone" => nil))])

      result = importer.call

      expect(result.addresses).to eq(1)
      expect(Spree.user_class.find_by(b2b_customer_id: 5001).bill_address.phone).to be_blank
    end

    it "still imports the user when the address cannot be resolved" do
      # Mirrors the one real UK customer: GB has regions on file, but "Essex"
      # is not among them, so the address is dropped and the account is not.
      great_britain = create(:country, iso: "GB", name: "United Kingdom")
      create(:state, country: great_britain, name: "Greater London", abbr: "LND")
      write_customers([record("address" => address("state" => "Essex", "country_iso" => "GB"))])

      result = importer.call

      expect(result.failures).to be_empty
      expect(result.addresses).to eq(0)
      expect(Spree.user_class.find_by(b2b_customer_id: 5001)).to be_present
    end

    it "does not duplicate the address on re-run" do
      write_customers([record("address" => address)])
      importer.call

      result = described_class.new(data_file: data_file).call

      expect(result.addresses).to eq(0)
      expect(Spree::Address.count).to eq(1)
    end
  end

  it "isolates a failing record so the rest still import" do
    write_customers([record, record("b2b_customer_id" => 5002, "email" => nil)])

    result = importer.call

    expect(result.created).to eq(1)
    expect(result.failures.size).to eq(1)
    expect(Spree.user_class.find_by(b2b_customer_id: 5001)).to be_present
  end
end
