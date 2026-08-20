# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# The point of this class is to answer one question the rest of the app cannot:
# is anything actually running the jobs we enqueue? Enqueuing succeeds either
# way, so without this the failure is invisible.
RSpec.describe Nsb::QueueHealth do
  subject(:health) { described_class.new }

  describe "when Active Job is not on a durable adapter" do
    before { ActiveJob::Base.queue_adapter = :test }

    it "names the adapter in use" do
      expect(health.adapter).to eq("Test")
      expect(health).not_to be_solid_queue
    end

    it "reports nothing rather than querying tables that may not apply" do
      expect(health.live_processes).to be_empty
      expect(health.pending_count).to eq(0)
      expect(health.failed_count).to eq(0)
      expect(health.oldest_pending_at).to be_nil
      expect(health.recent_failures).to be_empty
    end
  end

  describe "when Solid Queue is the adapter" do
    before { ActiveJob::Base.queue_adapter = :solid_queue }

    after do
      ActiveJob::Base.queue_adapter = :test
      SolidQueue::Job.delete_all
      SolidQueue::Process.delete_all
    end

    it "identifies the adapter" do
      expect(health.adapter).to eq("SolidQueue")
      expect(health).to be_solid_queue
    end

    context "with no worker process registered" do
      it "reports that nothing is draining the queue" do
        expect(health.draining?).to be(false)
        expect(health.live_processes).to be_empty
      end

      it "still counts the jobs piling up, because they are not lost" do
        create(:user).then { |user| Nsb::ClaimMailer.claim_instructions(user, "t").deliver_later }

        expect(health.pending_count).to eq(1)
        expect(health.oldest_pending_at).to be_present
      end
    end

    context "with a live worker" do
      before { register_process("Worker", heartbeat: Time.current) }

      it "reports the queue as being drained" do
        expect(health.draining?).to be(true)
        expect(health.live_processes).to eq([ "Worker" ])
      end
    end

    context "with a worker whose heartbeat has gone stale" do
      # What a hard kill leaves behind: the row is still there, the process is
      # not. Treating it as alive would mask exactly the outage this class is
      # meant to catch.
      before { register_process("Worker", heartbeat: 30.minutes.ago) }

      it "does not count it as draining the queue" do
        expect(health.draining?).to be(false)
        expect(health.live_processes).to be_empty
      end
    end

    describe "failed jobs" do
      it "reports none when there are none" do
        expect(health.failed_count).to eq(0)
        expect(health.recent_failures).to be_empty
      end

      it "summarises them with the job class and the first line of the error" do
        user = create(:user)
        Nsb::ClaimMailer.claim_instructions(user, "t").deliver_later
        job = SolidQueue::Job.last
        SolidQueue::FailedExecution.create!(job: job, error: "Net::OpenTimeout: execution expired\nbacktrace line")

        failure = health.recent_failures.first

        expect(health.failed_count).to eq(1)
        expect(failure[:job_class]).to eq("ActionMailer::MailDeliveryJob")
        expect(failure[:error]).to eq("Net::OpenTimeout: execution expired")
      end
    end
  end

  def register_process(kind, heartbeat:)
    SolidQueue::Process.create!(
      kind: kind,
      last_heartbeat_at: heartbeat,
      pid: 1234,
      name: "#{kind.downcase}-#{SecureRandom.hex(4)}"
    )
  end
end
