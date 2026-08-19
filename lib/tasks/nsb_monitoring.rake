# frozen_string_literal: true

namespace :nsb do
  namespace :monitoring do
    desc "Send a test error to Sentry to prove monitoring works end to end"
    task test: :environment do
      unless Sentry.initialized?
        abort <<~SETUP
          Sentry is not initialised.

          In development that is expected -- it only runs when SENTRY_DSN is set
          and Rails.env is production. To test from here:

            SENTRY_DSN=<your dsn> RAILS_ENV=production \\
            SECRET_KEY_BASE=$(openssl rand -hex 32) \\
            DATABASE_URL=postgres://localhost/nsb_wholesale_development \\
            bin/rails nsb:monitoring:test

          On Render, run this from the service Shell.
        SETUP
      end

      event = Sentry.capture_message(
        "Test event from nsb:monitoring:test at #{Time.zone.now}",
        level: :warning
      )

      if event
        # capture_message returns the event object, not an id string.
        puts "Sent to Sentry (event #{event.event_id})."
        puts "It should appear in your Sentry issues within a few seconds."
        puts "If it does not, the DSN is wrong or outbound HTTPS is blocked."
      else
        abort "Sentry accepted no event. Check SENTRY_DSN."
      end
    end

    desc "Show what monitoring and alerting is currently active"
    task status: :environment do
      puts "Sentry initialised   : #{Sentry.initialized?}"
      puts "SENTRY_DSN set       : #{ENV['SENTRY_DSN'].present?}"
      puts "Rails env            : #{Rails.env}"
      puts
      puts "Mail (order confirmations, account claims)"
      puts "  SMTP configured    : #{defined?(MailDelivery) ? MailDelivery.configured? : 'n/a'}"
      puts
      puts "ShipStation"
      config = Nsb::Shipstation::Configuration.new
      puts "  configured         : #{config.configured?}"
      puts "  pushes enabled     : #{config.enabled?}"
      puts "  store id           : #{config.store_id.inspect}"
      puts
      puts "Square"
      square = Nsb::Square::Configuration.new
      puts "  configured         : #{square.configured?}"
      puts "  environment        : #{square.environment}"
    end
  end
end
