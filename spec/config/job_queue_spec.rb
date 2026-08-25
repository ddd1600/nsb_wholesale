# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# This app defers two things to Active Job, and both happen *after* the customer
# has already been charged: the order confirmation email and the ShipStation
# push. Under the :async adapter those jobs lived only in process memory, so a
# Render restart or redeploy discarded them silently -- nothing raised, nothing
# was logged, and the first sign of trouble was a customer who never got their
# email.
#
# What matters here is durability: an enqueued job must be a row in PostgreSQL
# before the request that enqueued it returns.
RSpec.describe "Background job durability" do
  describe "the Solid Queue adapter" do
    # This has to be a `before`, not an `around`. The suite-wide hook in
    # spec/solidus_starter_frontend_spec_helper.rb sets the :test adapter before
    # every example, and an `around` would be undone by it.
    before { ActiveJob::Base.queue_adapter = :solid_queue }

    after do
      ActiveJob::Base.queue_adapter = :test
      SolidQueue::Job.delete_all
    end

    let(:user) { create(:user, email: "wholesale@example.com") }

    it "writes an enqueued job to the database instead of holding it in memory" do
      expect {
        Nsb::ClaimMailer.claim_instructions(user, "raw-token").deliver_later
      }.to change(SolidQueue::Job, :count).by(1)

      expect(SolidQueue::Job.last.class_name).to eq("ActionMailer::MailDeliveryJob")
    end

    it "leaves the job claimable by a worker in another process" do
      Nsb::ClaimMailer.claim_instructions(user, "raw-token").deliver_later

      job = SolidQueue::Job.last

      # A ready_execution row is what a worker polls for. Without it the job
      # would be stored but never picked up.
      expect(SolidQueue::ReadyExecution.where(job_id: job.id)).to exist
      expect(job.finished_at).to be_nil
    end

    it "persists the job's arguments, so a restart loses no context" do
      Nsb::ClaimMailer.claim_instructions(user, "raw-token").deliver_later

      arguments = SolidQueue::Job.last.arguments

      expect(arguments["job_class"]).to eq("ActionMailer::MailDeliveryJob")
      expect(arguments["arguments"]).to include("Nsb::ClaimMailer", "claim_instructions")
    end

    it "stores the ShipStation push too, since it runs after payment" do
      order = create(:order, number: "R100000001")

      expect {
        Nsb::PushOrderToShipstationJob.perform_later(order)
      }.to change { SolidQueue::Job.where(class_name: "Nsb::PushOrderToShipstationJob").count }.by(1)
    end
  end

  # These read configuration files rather than exercising behaviour, because the
  # production environment cannot be booted from inside the test environment.
  # They are regression guards, not proof that the queue works: their only job is
  # to fail loudly if the durable adapter is reverted, or if the process that
  # drains the queue stops being started.
  describe "production configuration (file guards)" do
    it "uses the solid_queue adapter, not :async" do
      config = Rails.root.join("config/environments/production.rb").read

      expect(config).to match(/^\s*config\.active_job\.queue_adapter = :solid_queue$/)
    end

    it "starts a supervisor inside Puma, so something actually drains the queue" do
      puma = Rails.root.join("config/puma.rb").read

      expect(puma).to include("plugin :solid_queue")
      expect(puma).to include("solid_queue_mode :async")
    end

    # Regression: Render sets WEB_CONCURRENCY=1 on its own, which put Puma in
    # cluster mode. The cluster master never loads the Rails app, so the
    # plugin's after_booted hook raised `uninitialized constant SolidQueue` and
    # the service crash-looped on boot. `workers 0` overrides Puma's own
    # WEB_CONCURRENCY default and forces single mode.
    it "forces Puma into single mode, which the plugin requires" do
      puma = Rails.root.join("config/puma.rb").read

      expect(puma).to match(/^workers 0$/)
    end

    it "sets SOLID_QUEUE_IN_PUMA on Render, which is what enables that plugin" do
      render_config = YAML.load_file(Rails.root.join("render.yaml"))
      web = render_config["services"].find { |service| service["name"] == "nsb-wholesale" }
      variable = web["envVars"].find { |var| var["key"] == "SOLID_QUEUE_IN_PUMA" }

      expect(variable).to include("value" => "true")
    end

    it "keeps the queue tables in the primary database, with no second database" do
      config = Rails.root.join("config/environments/production.rb").read

      expect(config).not_to match(/config\.solid_queue\.connects_to/)
      expect(ActiveRecord::Base.connection.table_exists?("solid_queue_jobs")).to be(true)
    end
  end
end
