# frozen_string_literal: true

module Nsb
  module Square
    # Square credentials and environment, read only from ENV.
    #
    # Nothing here is ever committed, and development/test must point at
    # Square's Sandbox while production points at the live account -- separate
    # credentials, per CLAUDE.md. The two are different tokens entirely, so the
    # only way to charge a real card from a laptop is to deliberately export a
    # production token.
    #
    # Required:
    #   SQUARE_ACCESS_TOKEN   - Sandbox token in dev/test, production token on Render. SECRET.
    #   SQUARE_LOCATION_ID    - the location payments are attributed to
    #   SQUARE_APPLICATION_ID - identifies the app to the browser SDK. NOT secret:
    #                           it is embedded in the page source by design.
    # Optional:
    #   SQUARE_ENVIRONMENT    - "sandbox" (default outside production) or "production"
    class Configuration
      SANDBOX_URL = "https://connect.squareupsandbox.com"
      PRODUCTION_URL = "https://connect.squareup.com"

      # Web Payments SDK. Sandbox and production are different scripts; loading
      # the wrong one produces tokens the other environment will reject.
      SANDBOX_JS = "https://sandbox.web.squarecdn.com/v1/square.js"
      PRODUCTION_JS = "https://web.squarecdn.com/v1/square.js"

      class MissingCredentials < StandardError; end

      def access_token
        ENV["SQUARE_ACCESS_TOKEN"].presence
      end

      def location_id
        ENV["SQUARE_LOCATION_ID"].presence
      end

      # Public value, rendered into the checkout page for the browser SDK.
      def application_id
        ENV["SQUARE_APPLICATION_ID"].presence
      end

      def js_sdk_url
        production? ? PRODUCTION_JS : SANDBOX_JS
      end

      # The browser needs application_id and location_id; the access token must
      # never leave the server.
      def browser_configured?
        application_id.present? && location_id.present?
      end

      # Defaults to sandbox everywhere except production, so a misconfigured
      # laptop cannot reach the live account by accident.
      def environment
        ENV["SQUARE_ENVIRONMENT"].presence || (Rails.env.production? ? "production" : "sandbox")
      end

      def production?
        environment == "production"
      end

      def base_url
        production? ? PRODUCTION_URL : SANDBOX_URL
      end

      def currency
        Spree::Config.currency
      end

      def configured?
        access_token.present? && location_id.present?
      end

      def client
        unless configured?
          missing = []
          missing << "SQUARE_ACCESS_TOKEN" if access_token.blank?
          missing << "SQUARE_LOCATION_ID" if location_id.blank?
          raise MissingCredentials,
            "Square is not configured - missing #{missing.join(', ')}. " \
            "Use Sandbox credentials outside production."
        end

        @client ||= ::Square::Client.new(token: access_token, base_url: base_url)
      end
    end
  end
end
