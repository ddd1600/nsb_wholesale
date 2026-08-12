# frozen_string_literal: true

module Nsb
  # Imports B2BWave customers as Solidus users from db/import_data/customers.json.
  #
  # Accounts are created WITHOUT a usable password. B2BWave never exposed
  # password hashes, so every account starts with a long random secret that
  # nobody -- including us -- knows. The only way in is the email-verified claim
  # flow, which proves the person controls the address before letting them set a
  # password.
  #
  # Safe to re-run: keyed on b2b_customer_id. A re-import never touches
  # encrypted_password, so it cannot lock out a customer who has already
  # claimed their account.
  #
  # NOTE: customers.json holds PII and is gitignored, so unlike the catalog this
  # is a one-time migration run against the target database, not a deploy step.
  class CustomerImporter
    DATA_FILE = Rails.root.join("db/import_data/customers.json")

    Result = Struct.new(:created, :updated, :addresses, :failures, keyword_init: true) do
      def to_s
        "created=#{created} updated=#{updated} addresses=#{addresses} failures=#{failures.size}"
      end
    end

    def initialize(data_file: DATA_FILE, logger: Rails.logger)
      @data_file = Pathname(data_file)
      @logger = logger
      @result = Result.new(created: 0, updated: 0, addresses: 0, failures: [])
    end

    def call
      records = JSON.parse(@data_file.read)
      say "importing #{records.size} customers"

      records.each do |record|
        ActiveRecord::Base.transaction { import_customer(record) }
      rescue => error
        @result.failures << { email: record["email"], error: error.message }
        say "  FAILED  #{record['email']}  #{error.message}"
      end

      say "done: #{@result}"
      @result
    end

    private

    def import_customer(record)
      user = Spree.user_class.find_or_initialize_by(b2b_customer_id: record["b2b_customer_id"])
      new_record = user.new_record?

      user.email = record["email"]

      # Only ever set a password on creation. Re-running the import must not
      # disturb a customer who has already set their own.
      if new_record
        user.password = SecureRandom.base58(48)
        user.password_confirmation = user.password
      end

      # Everything B2BWave held, kept verbatim. Most customers have no usable
      # address, so this is where their company details survive.
      user.admin_metadata = (user.admin_metadata || {}).merge(
        "b2bwave" => record["source"].compact
      )

      user.save!
      import_address(user, record) if record["address"].present?

      new_record ? @result.created += 1 : @result.updated += 1
    end

    def import_address(user, record)
      attributes = record["address"]
      country = Spree::Country.find_by(iso: attributes["country_iso"])
      return unless country

      state = find_state(country, attributes["state"])
      # Solidus requires a state whenever the country has them on file.
      return if country.states.any? && state.nil?

      address = Spree::Address.new(
        name: attributes["name"] || record["company_name"],
        company: attributes["company"],
        address1: attributes["address1"],
        address2: attributes["address2"],
        city: attributes["city"],
        zipcode: attributes["zipcode"],
        phone: attributes["phone"],
        country: country,
        state: state,
        state_name: state ? nil : attributes["state"]
      )
      return unless address.valid?

      # Reuse an identical existing address so re-runs don't pile up duplicates.
      existing = user.bill_address
      return if existing && same_address?(existing, address)

      address.save!
      user.update!(bill_address: address, ship_address: address)
      @result.addresses += 1
    end

    # B2BWave stores states inconsistently -- "SC" in some rows, "South Carolina"
    # in others -- so try both the abbreviation and the full name.
    def find_state(country, value)
      return nil if value.blank?

      country.states.find_by("lower(abbr) = :v OR lower(name) = :v", v: value.to_s.strip.downcase)
    end

    def same_address?(existing, candidate)
      %i[address1 address2 city zipcode country_id state_id].all? do |attribute|
        existing.public_send(attribute) == candidate.public_send(attribute)
      end
    end

    def say(message)
      @logger.info("[customer-import] #{message}")
      puts message if $stdout.tty? || Rails.env.development?
    end
  end
end
