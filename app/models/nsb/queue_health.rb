# frozen_string_literal: true

module Nsb
  # A read-only snapshot of the background job queue, for nsb:monitoring:queue.
  #
  # This exists because a queue with nothing draining it fails silently. Jobs are
  # still accepted -- enqueuing writes a row and returns happily -- they just
  # never run. An order confirmation email that never arrives then looks exactly
  # like a mail problem, and the ShipStation push looks like a ShipStation
  # problem. The distinguishing fact is whether a worker is heartbeating, and
  # nothing else in the app reports that.
  #
  # Kept as a plain object rather than living in the rake task so the logic can
  # be tested without invoking Rake.
  class QueueHealth
    # A worker writes a heartbeat every few seconds. Anything older than this is
    # treated as a dead process whose row was never cleaned up -- which is what
    # a hard kill leaves behind.
    HEARTBEAT_WINDOW = 5.minutes

    def adapter
      ActiveJob::Base.queue_adapter.class.name.demodulize.sub("Adapter", "")
    end

    def solid_queue?
      adapter == "SolidQueue"
    end

    # The processes currently claiming to be alive, by kind: Supervisor,
    # Dispatcher, Worker, and Scheduler when recurring tasks are configured.
    def live_processes
      return [] unless solid_queue?

      SolidQueue::Process.where(last_heartbeat_at: HEARTBEAT_WINDOW.ago..).order(:kind).map(&:kind)
    end

    # The question this class exists to answer.
    def draining?
      live_processes.any?
    end

    def pending_count
      solid_queue? ? pending_jobs.count : 0
    end

    def failed_count
      solid_queue? ? SolidQueue::FailedExecution.count : 0
    end

    def oldest_pending_at
      return nil unless solid_queue?

      pending_jobs.minimum(:created_at)
    end

    # Most recent first, since a burst of failures usually shares one cause and
    # the latest is the one still happening.
    def recent_failures(limit: 5)
      return [] unless solid_queue?

      SolidQueue::FailedExecution.order(created_at: :desc).limit(limit).map do |execution|
        {
          id: execution.id,
          job_class: execution.job.class_name,
          error: execution.error.to_s.lines.first&.strip
        }
      end
    end

    private

    def pending_jobs
      SolidQueue::Job.where(finished_at: nil)
    end
  end
end
