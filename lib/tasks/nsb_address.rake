# frozen_string_literal: true

namespace :nsb do
  namespace :address do
    desc "Check Google Address Validation (ADDRESS=\"...\" to test a specific one)"
    task check: :environment do
      # An env var rather than a rake argument: addresses are full of commas,
      # which rake treats as argument separators.
      report = Nsb::AddressValidationCheck.new(ENV["ADDRESS"]).call

      puts
      puts "=" * 72
      puts "Address validation: #{report.headline}"
      puts
      report.details.each { |line| puts "  #{line}" }
      puts

      # Non-zero on failure so this is usable in a script, but note the form is
      # never blocked by any of these -- see Nsb::AddressValidator.
      abort "Not working yet." unless report.ok
      puts "All good."
    end
  end
end
