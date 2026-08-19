# frozen_string_literal: true

# Error monitoring.
#
# Inert unless SENTRY_DSN is set, so development and test are untouched and
# nothing is reported from a laptop. Set it in Render only.
#
# The point of this for a deliberately hands-off operator: a failed ShipStation
# push, a bounced order confirmation, or an OAuth refresh token that Google has
# revoked all currently surface as a line in a log nobody reads. This turns them
# into an email.
return if ENV["SENTRY_DSN"].blank?

Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.environment = Rails.env
  config.enabled_environments = %w[production]

  # PII stays out. Never send request bodies, cookies, or user IP addresses:
  # this app handles wholesale customers' names, addresses and order history,
  # and an error tracker is not the place for any of it.
  config.send_default_pii = false

  # Belt and braces on top of send_default_pii. Rails' filter_parameters already
  # covers these in logs; repeat them here so a payload built by Sentry itself
  # cannot leak one.
  config.before_send = lambda do |event, _hint|
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    event.request&.data = filter.filter(event.request.data) if event.request&.data.is_a?(Hash)
    event
  end

  # No performance tracing. It is the expensive part of Sentry's free tier and
  # this app serves roughly one order a day -- errors are what matter here.
  config.traces_sample_rate = 0.0

  # Background jobs are where silent failures actually happen: the ShipStation
  # push and the order confirmation email both run through ActiveJob.
  config.rails.report_rescued_exceptions = true

  # Noise that is not worth an email.
  config.excluded_exceptions += [
    "ActionController::RoutingError",
    "ActiveRecord::RecordNotFound",
    "ActionController::InvalidAuthenticityToken"
  ]

  # Lets a release be identified in Sentry without wiring up a deploy hook.
  config.release = ENV["RENDER_GIT_COMMIT"].presence
end
