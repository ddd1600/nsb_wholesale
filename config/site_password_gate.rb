# frozen_string_literal: true

# Temporary site-wide password gate.
#
# Keeps the portal closed while it is being finished. Everything behind it is
# unchanged -- this only decides whether a request gets through at all.
#
# Rack middleware rather than a controller before_action, deliberately: Solidus's
# admin controllers descend from Spree::Admin::BaseController, not this app's
# ApplicationController, so a controller filter would leave /admin open. At this
# level nothing is missed.
#
# Enabled only when SITE_PASSWORD is set, so development and test are untouched
# and there is no password committed to the repository. Remove the env var in
# Render to open the site; delete this file and its require to remove the
# feature entirely.
#
# Lives in config/ rather than lib/ because config/application.rb loads before
# Zeitwerk is ready, and lib/ is autoloaded -- the same reason as
# config/mail_delivery.rb.
class SitePasswordGate
  # Render polls this to decide whether the service is healthy. Gating it would
  # make every deploy look like a failed one and take the site down.
  OPEN_PATHS = ["/up"].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) unless gate_enabled?
    return @app.call(env) if open_path?(env["PATH_INFO"])
    return @app.call(env) if authorised?(env)

    unauthorised
  end

  private

  def password
    ENV["SITE_PASSWORD"].presence
  end

  def gate_enabled?
    password.present?
  end

  def open_path?(path)
    OPEN_PATHS.include?(path)
  end

  def authorised?(env)
    auth = Rack::Auth::Basic::Request.new(env)
    return false unless auth.provided? && auth.basic?

    # Any username; only the password matters. secure_compare avoids leaking
    # length/content through timing -- cheap, and there is no reason not to.
    _user, given = auth.credentials
    given.present? && ActiveSupport::SecurityUtils.secure_compare(given, password)
  end

  def unauthorised
    [
      401,
      {
        "WWW-Authenticate" => 'Basic realm="New South Botanicals Wholesale", charset="UTF-8"',
        "Content-Type" => "text/html; charset=utf-8"
      },
      [<<~HTML]
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><title>Coming soon</title></head>
        <body style="font-family: system-ui, sans-serif; max-width: 32rem; margin: 20vh auto; padding: 0 1rem; text-align: center;">
          <h1 style="font-weight: 600;">New South Botanicals Wholesale</h1>
          <p>This portal is not open yet. Please enter the password to continue.</p>
        </body></html>
      HTML
    ]
  end
end
