# frozen_string_literal: true

namespace :nsb do
  namespace :address do
    desc "Check the Google Address Validation setup end to end (makes one live call)"
    task check: :environment do
      report = Nsb::AddressValidationCheck.new.call

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
