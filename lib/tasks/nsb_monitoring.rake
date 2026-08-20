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
      puts
      Rake::Task["nsb:monitoring:queue"].invoke
    end

    # The queue is the one piece here that can fail completely silently. Jobs are
    # still accepted when nothing is draining them -- they simply accumulate,
    # and the order confirmation email that never arrives looks identical to a
    # mail problem. This is the command that tells the difference.
    desc "Show background job queue health"
    task queue: :environment do
      adapter = ActiveJob::Base.queue_adapter.class.name.demodulize.sub("Adapter", "")

      puts "Background jobs"
      puts "  adapter            : #{adapter}"

      unless adapter == "SolidQueue"
        puts "  NOTE: not Solid Queue, so pending jobs are held in memory and"
        puts "        lost on restart. Expected in development; a problem in production."
        next
      end

      alive = SolidQueue::Process.where(last_heartbeat_at: 5.minutes.ago..).order(:kind)
      pending = SolidQueue::Job.where(finished_at: nil).count
      failed = SolidQueue::FailedExecution.count
      oldest = SolidQueue::Job.where(finished_at: nil).minimum(:created_at)

      puts "  workers running    : #{alive.any? ? alive.map(&:kind).join(', ') : 'NONE'}"
      puts "  pending jobs       : #{pending}"
      puts "  failed jobs        : #{failed}"
      puts "  oldest pending     : #{oldest ? "#{oldest} (#{time_ago_in_words(oldest)} ago)" : 'none'}"

      if alive.none?
        puts
        puts "  NOTHING IS DRAINING THE QUEUE. Jobs are being stored but never run."
        puts "  In production this means SOLID_QUEUE_IN_PUMA is not set on the"
        puts "  Render service -- set it to \"true\" and redeploy. Nothing is lost"
        puts "  in the meantime; the jobs run as soon as a worker starts."
      end

      if failed.positive?
        puts
        puts "  Failed jobs, most recent first:"
        SolidQueue::FailedExecution.order(created_at: :desc).limit(5).each do |execution|
          puts "    #{execution.job.class_name} -- #{execution.error.to_s.lines.first&.strip}"
        end
        puts "  Retry one with: SolidQueue::FailedExecution.find(<id>).retry"
      end
    end

    def time_ago_in_words(time)
      ActionController::Base.helpers.time_ago_in_words(time)
    end
  end
end
