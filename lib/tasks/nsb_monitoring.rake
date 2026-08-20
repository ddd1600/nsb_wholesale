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
      # Render sets this to the deployed commit. It is the only way from inside
      # the running service to tell which code is actually live -- useful when a
      # deploy is expected but the behaviour has not changed.
      puts "Running commit       : #{ENV['RENDER_GIT_COMMIT'].presence || 'unknown (not on Render)'}"
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
      puts
      Rake::Task["nsb:monitoring:queue"].invoke
    end

    # The queue is the one piece here that can fail completely silently. Jobs are
    # still accepted when nothing is draining them -- they simply accumulate,
    # and the order confirmation email that never arrives looks identical to a
    # mail problem. This is the command that tells the difference.
    #
    # The logic lives in Nsb::QueueHealth so it can be tested; this only prints.
    desc "Show background job queue health"
    task queue: :environment do
      health = Nsb::QueueHealth.new

      puts "Background jobs"
      puts "  adapter            : #{health.adapter}"

      unless health.solid_queue?
        puts "  NOTE: not Solid Queue, so pending jobs are held in memory and"
        puts "        lost on restart. Expected in development; a problem in production."
        next
      end

      oldest = health.oldest_pending_at
      ago = ActionController::Base.helpers

      puts "  workers running    : #{health.draining? ? health.live_processes.join(', ') : 'NONE'}"
      puts "  pending jobs       : #{health.pending_count}"
      puts "  failed jobs        : #{health.failed_count}"
      puts "  oldest pending     : #{oldest ? "#{oldest} (#{ago.time_ago_in_words(oldest)} ago)" : 'none'}"

      unless health.draining?
        puts
        puts "  NOTHING IS DRAINING THE QUEUE. Jobs are being stored but never run."
        puts "  In production this means SOLID_QUEUE_IN_PUMA is not set on the"
        puts "  Render service -- set it to \"true\" and redeploy. Nothing is lost"
        puts "  in the meantime; the jobs run as soon as a worker starts."
      end

      if health.failed_count.positive?
        puts
        puts "  Failed jobs, most recent first:"
        health.recent_failures.each do |failure|
          puts "    [#{failure[:id]}] #{failure[:job_class]} -- #{failure[:error]}"
        end
        puts "  Retry one with: SolidQueue::FailedExecution.find(<id>).retry"
      end
    end
  end
end
