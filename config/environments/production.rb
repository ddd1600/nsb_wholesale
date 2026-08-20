require "active_support/core_ext/integer/time"
require_relative "../mail_delivery"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files in PostgreSQL (see config/storage.yml). Render wipes the
  # container filesystem on every deploy, so :local would lose every image.
  config.active_storage.service = :db

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :mem_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  #
  # :async (the Rails default) keeps queued jobs in process memory, so every
  # pending job is lost when Render restarts or redeploys this service. The two
  # things this app defers to a job -- the order confirmation email and the
  # ShipStation push -- both happen after the customer has already been charged,
  # so losing one is silent and only discovered by a customer who never got
  # their email.
  #
  # No connects_to here on purpose: the Solid Queue tables live in the primary
  # database (see the CreateSolidQueueTables migration), not a separate queue
  # database. The supervisor runs inside Puma -- see config/puma.rb.
  config.active_job.queue_adapter = :solid_queue

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Host for links in mailer templates. Solidus prefers Spree::Store#url and
  # falls back to this; APP_HOST lets Render set it without a deploy.
  config.action_mailer.default_url_options = {
    host: ENV.fetch("APP_HOST", "wholesale.newsouthbotanicals.com"),
    protocol: "https"
  }

  # SMTP settings live in config/mail_delivery.rb -- one place, read from the
  # environment. Do not add smtp_settings here.
  MailDelivery.apply!(config)

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
