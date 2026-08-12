# frozen_string_literal: true

# The one place outbound mail delivery is configured.
#
# Lives in config/ rather than lib/ or config/initializers/ on purpose:
# environment files load BEFORE initializers, so an initializer would be too
# late for production.rb to call; and lib/ is autoloaded by Zeitwerk, which
# conflicts with the explicit require_relative that environment files need.
#
# Per EMAIL_SETUP.md, transactional mail goes through Google Workspace SMTP as
# connect@newsouthbotanicals.com rather than a dedicated ESP -- CBD/hemp is a
# restricted category at several ESPs, and an account termination would silently
# stop order confirmations. That decision is settled; don't re-open it here.
#
# AUTH: OAuth2 (XOAUTH2), not an app password. Google App Passwords are
# unavailable on this Workspace account, and Google ended plain username/password
# SMTP for Workspace in May 2025. Net::SMTP speaks XOAUTH2 natively
# (Net::SMTP::AuthXoauth2), so no extra gem is needed -- the "password" is simply
# a short-lived OAuth access token.
#
# Access tokens expire roughly hourly, so the token is NOT baked into these
# settings at boot. Nsb::GmailOauthInterceptor injects a fresh one immediately
# before each delivery (registered in config/initializers/mail_oauth.rb).
#
# Credentials come only from the environment. Nothing here is ever committed.

module MailDelivery
  # Injects a fresh OAuth access token as the SMTP password immediately before
  # each delivery. Gmail's XOAUTH2 "password" expires roughly hourly, so it
  # cannot live in the static smtp_settings built at boot; interceptors run at
  # the last moment before the message is handed to the delivery method.
  #
  # Defined here, in a plain required file, rather than under app/ -- an
  # autoloaded constant cannot be resolved while initializers run, and a
  # reloadable one would leave a stale copy registered after every code reload.
  # Nsb::GmailOauthToken is referenced lazily inside the method, by which time
  # autoloading is available.
  module TokenInterceptor
    def self.delivering_email(message)
      delivery_method = message.delivery_method
      return unless delivery_method.respond_to?(:settings)

      settings = delivery_method.settings
      return unless settings.is_a?(Hash)
      return unless settings[:authentication].to_s == "xoauth2"

      settings[:password] = Nsb::GmailOauthToken.access_token
    end
  end

  # Env vars that must be present for OAuth2 SMTP to work. Obtain the refresh
  # token once with: bin/rails nsb:mail:authorize
  REQUIRED_ENV = %w[
    SMTP_USER_NAME
    GMAIL_OAUTH_CLIENT_ID
    GMAIL_OAUTH_CLIENT_SECRET
    GMAIL_OAUTH_REFRESH_TOKEN
  ].freeze

  SMTP_SETTINGS = {
    address: ENV.fetch("SMTP_ADDRESS", "smtp.gmail.com"),
    port: Integer(ENV.fetch("SMTP_PORT", 587)),
    domain: ENV.fetch("SMTP_DOMAIN", "newsouthbotanicals.com"),
    user_name: ENV["SMTP_USER_NAME"],
    # Deliberately blank. The interceptor sets this per delivery; a token stored
    # here at boot would be stale within the hour.
    password: nil,
    authentication: :xoauth2,
    enable_starttls_auto: true,
    # Fail fast rather than hanging a request on an unreachable SMTP host.
    open_timeout: 10,
    read_timeout: 10
  }.freeze

  def self.missing_env
    REQUIRED_ENV.reject { |key| ENV[key].present? }
  end

  # True only when the environment carries every credential. Lets production
  # boot (and keep taking orders) even if mail is not configured yet, instead of
  # crashing on startup mid-migration.
  def self.configured?
    missing_env.empty?
  end

  def self.apply!(config)
    unless configured?
      # Deliberately not raising: an unconfigured mailer must not take the
      # storefront down. Deliveries are disabled so nothing fails halfway
      # through an SMTP conversation instead.
      config.action_mailer.perform_deliveries = false
      # Rails.logger does not exist yet while environment files load, so write
      # to stderr -- Render captures it in the service log either way.
      Kernel.warn(
        "[mail] outbound email DISABLED - missing #{missing_env.join(', ')}. " \
        "Run `bin/rails nsb:mail:authorize` once to obtain a refresh token, then set these in Render."
      )
      return
    end

    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = SMTP_SETTINGS
    config.action_mailer.perform_deliveries = true
    # Surface SMTP failures in logs rather than swallowing them. Safe because
    # mail is delivered out-of-band via deliver_later, so a raised error cannot
    # roll back a customer's order (see spec/models/order_confirmation_delivery_spec.rb).
    config.action_mailer.raise_delivery_errors = true
  end
end
