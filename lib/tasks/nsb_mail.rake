# frozen_string_literal: true

namespace :nsb do
  namespace :mail do
    desc "One-time: obtain a Google OAuth refresh token for SMTP sending"
    task :authorize do
      require "net/http"
      require "uri"
      require "json"
      require "securerandom"

      client_id = ENV["GMAIL_OAUTH_CLIENT_ID"]
      client_secret = ENV["GMAIL_OAUTH_CLIENT_SECRET"]

      if client_id.blank? || client_secret.blank?
        abort <<~SETUP
          Set GMAIL_OAUTH_CLIENT_ID and GMAIL_OAUTH_CLIENT_SECRET first.

          To create them:
            1. console.cloud.google.com -> create (or pick) a project
            2. APIs & Services -> OAuth consent screen -> User Type: INTERNAL
               (Internal avoids Google's app-verification review. It works
                because connect@ is in your own Workspace.)
            3. APIs & Services -> Credentials -> Create credentials
               -> OAuth client ID -> Application type: Desktop app
            4. Copy the client ID and secret, then re-run:

               GMAIL_OAUTH_CLIENT_ID=... GMAIL_OAUTH_CLIENT_SECRET=... bin/rails nsb:mail:authorize
        SETUP
      end

      # Loopback redirect. Nothing needs to be listening -- the browser will show
      # a connection error, and the authorisation code sits in the address bar.
      redirect_uri = "http://localhost:8080"

      auth_url = URI("https://accounts.google.com/o/oauth2/v2/auth")
      auth_url.query = URI.encode_www_form(
        client_id: client_id,
        redirect_uri: redirect_uri,
        response_type: "code",
        # Full SMTP send scope. Gmail's SMTP endpoint requires this one.
        scope: "https://mail.google.com/",
        # offline + consent is what makes Google return a REFRESH token rather
        # than only a one-hour access token.
        access_type: "offline",
        prompt: "consent"
      )

      puts <<~STEPS

        1. Open this URL while signed in as connect@newsouthbotanicals.com:

        #{auth_url}

        2. Approve access. The browser will fail to load localhost:8080 -- that is expected.
        3. Copy the value of `code=` from the address bar (everything up to the next & if present).

      STEPS

      print "Paste the code here: "
      code = $stdin.gets.to_s.strip
      abort "No code entered." if code.empty?

      response = Net::HTTP.post_form(
        URI("https://oauth2.googleapis.com/token"),
        "code" => CGI.unescape(code),
        "client_id" => client_id,
        "client_secret" => client_secret,
        "redirect_uri" => redirect_uri,
        "grant_type" => "authorization_code"
      )

      unless response.is_a?(Net::HTTPSuccess)
        abort "Google rejected the code (HTTP #{response.code}): #{response.body}"
      end

      payload = JSON.parse(response.body)
      refresh_token = payload["refresh_token"]

      if refresh_token.blank?
        abort <<~NO_TOKEN
          Google returned no refresh_token. This happens when the account has already
          granted this client. Revoke it at myaccount.google.com/permissions and re-run.
        NO_TOKEN
      end

      puts <<~DONE

        Success. Set these in Render (Environment -> Environment Variables).
        This is the only time the refresh token is shown -- it is not written to disk.

          SMTP_USER_NAME              connect@newsouthbotanicals.com
          GMAIL_OAUTH_CLIENT_ID       #{client_id}
          GMAIL_OAUTH_CLIENT_SECRET   (the secret you already have)
          GMAIL_OAUTH_REFRESH_TOKEN   #{refresh_token}

        Do not commit these. Clear your terminal scrollback when done.

      DONE
    end

    desc "Send a test email to verify OAuth SMTP end to end. Usage: rake nsb:mail:verify[you@example.com]"
    task :verify, [:recipient] => :environment do |_task, args|
      # Only production.rb requires this, so load it explicitly -- the task must
      # work in development too.
      require Rails.root.join("config/mail_delivery")

      recipient = args[:recipient]
      abort "Usage: bin/rails 'nsb:mail:verify[you@example.com]'" if recipient.blank?

      if MailDelivery.missing_env.any?
        abort "Missing: #{MailDelivery.missing_env.join(', ')}"
      end

      print "Refreshing OAuth access token... "
      Nsb::GmailOauthToken.reset!
      token = Nsb::GmailOauthToken.access_token
      puts "ok (#{token.length} chars, not shown)"

      # Send over real SMTP regardless of environment. Development normally uses
      # letter_opener, which would silently "succeed" without ever contacting
      # Gmail -- useless for verifying that OAuth actually works.
      settings = MailDelivery::SMTP_SETTINGS.merge(password: token)
      puts "Sending via #{settings[:address]}:#{settings[:port]} as #{settings[:user_name]}"

      message = Mail.new do
        to recipient
        from ENV.fetch("SMTP_USER_NAME")
        subject "NSB wholesale portal - SMTP test"
        body <<~BODY
          If you are reading this, OAuth2 SMTP works.

          Now open "Show original" on this message and confirm BOTH:
            DKIM: PASS
            SPF:  PASS

          Sent #{Time.current}
        BODY
      end
      message.delivery_method(:smtp, settings)

      print "Sending to #{recipient}... "
      begin
        message.deliver!
      rescue => error
        puts "FAILED"
        abort <<~HELP
          #{error.class}: #{error.message}

          Common causes:
            535 / invalid credentials -> the refresh token belongs to a different
              Google account than SMTP_USER_NAME. Re-run nsb:mail:authorize while
              signed in as #{ENV.fetch('SMTP_USER_NAME')}.
            Connection timeout -> port 587 blocked on this network.
        HELP
      end
      puts "sent"

      puts <<~NEXT

        Check the message in #{recipient}:
          - "Show original" shows dkim=pass AND spf=pass
          - From displays as #{ENV.fetch('SMTP_USER_NAME')} and was not rewritten
      NEXT
    end
  end
end
