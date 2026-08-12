# frozen_string_literal: true

require "net/http"

module Nsb
  # Exchanges the long-lived Google OAuth refresh token for a short-lived access
  # token, which is what Gmail's SMTP server accepts as the XOAUTH2 "password".
  #
  # Access tokens last about an hour. This caches one in process memory and
  # refreshes it a minute before expiry. In-process caching is fine here: the app
  # runs a single instance, and worst case each process fetches its own token.
  #
  # The token and refresh token are never logged. Failures raise with an
  # actionable message rather than returning nil, because a nil "password" would
  # surface as a confusing SMTP auth error instead of the real cause.
  class GmailOauthToken
    TOKEN_URI = URI("https://oauth2.googleapis.com/token")
    # Refresh slightly early so a token cannot expire mid-delivery.
    EXPIRY_MARGIN = 60

    class RefreshError < StandardError; end

    class << self
      def access_token
        mutex.synchronize do
          @access_token = nil if @expires_at.nil? || Time.current >= @expires_at
          @access_token ||= fetch!
        end
      end

      # Drops the cached token. Used by specs and by nsb:mail:verify.
      def reset!
        mutex.synchronize do
          @access_token = nil
          @expires_at = nil
        end
      end

      private

      def mutex
        @mutex ||= Mutex.new
      end

      def fetch!
        response = post_refresh

        unless response.is_a?(Net::HTTPSuccess)
          # Google names the cause in the body; it carries no secret material,
          # only codes like "invalid_grant". Match the hint to the actual code
          # rather than guessing -- a wrong hint sends you chasing the wrong fix.
          code = (JSON.parse(response.body)["error"] rescue nil)
          hint =
            case code
            when "invalid_client"
              "GMAIL_OAUTH_CLIENT_ID or GMAIL_OAUTH_CLIENT_SECRET is wrong or empty " \
                "(check you substituted real values, not placeholder dots)."
            when "invalid_grant"
              "GMAIL_OAUTH_REFRESH_TOKEN is revoked or belongs to a different Google " \
                "account than SMTP_USER_NAME. Re-run `bin/rails nsb:mail:authorize`."
            when "unauthorized_client"
              "The OAuth client is not permitted this grant type. Confirm it was created " \
                "as a Desktop app client."
            else
              "Re-run `bin/rails nsb:mail:authorize` if this persists."
            end

          raise RefreshError, "Google refused the OAuth refresh (HTTP #{response.code}): #{response.body.strip}. #{hint}"
        end

        payload = JSON.parse(response.body)
        @expires_at = Time.current + (payload.fetch("expires_in", 3600).to_i - EXPIRY_MARGIN).seconds
        payload.fetch("access_token")
      rescue JSON::ParserError, KeyError => error
        raise RefreshError, "Unexpected response from Google's token endpoint: #{error.message}"
      end

      def post_refresh
        Net::HTTP.post_form(
          TOKEN_URI,
          "client_id" => ENV.fetch("GMAIL_OAUTH_CLIENT_ID"),
          "client_secret" => ENV.fetch("GMAIL_OAUTH_CLIENT_SECRET"),
          "refresh_token" => ENV.fetch("GMAIL_OAUTH_REFRESH_TOKEN"),
          "grant_type" => "refresh_token"
        )
      end
    end
  end
end
