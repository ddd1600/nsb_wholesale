# frozen_string_literal: true

namespace :nsb do
  namespace :import do
    desc "Import the B2BWave catalog from db/import_data (safe to re-run)"
    task catalog: :environment do
      result = Nsb::CatalogImporter.new.call

      puts
      puts "=" * 60
      puts "catalog import: #{result}"

      if result.failures.any?
        puts "\nFAILURES:"
        result.failures.each { |failure| puts "  #{failure[:sku]}  #{failure[:name]}  -- #{failure[:error]}" }
        # Non-zero exit so a broken production import is not mistaken for success.
        abort "catalog import finished with #{result.failures.size} failure(s)"
      end
    end

    desc "Set the store's name, url and from-address (safe to re-run)"
    task store: :environment do
      Nsb::StoreConfigurator.new.call
    end

    desc "Create shipping methods from the rows B2BWave modelled as products (safe to re-run)"
    task shipping: :environment do
      result = Nsb::ShippingMethodImporter.new.call
      puts "shipping import: #{result}"
      abort "finished with #{result.failures.size} failure(s)" if result.failures.any?
    end

    desc "Import B2BWave customers from db/import_data/customers.json (safe to re-run)"
    task customers: :environment do
      result = Nsb::CustomerImporter.new.call

      puts
      puts "=" * 60
      puts "customer import: #{result}"
      puts "Accounts have no usable password; customers set one via the claim flow."

      if result.failures.any?
        puts "\nFAILURES:"
        result.failures.each { |failure| puts "  #{failure[:email]}  -- #{failure[:error]}" }
        abort "customer import finished with #{result.failures.size} failure(s)"
      end
    end
  end
end
