# frozen_string_literal: true

module Nsb
  # What hostname does this app believe it is reachable at?
  #
  # Two separate settings answer that, and Solidus reads them in different
  # places: Spree::Store#url is what Solidus builds order emails from, while
  # config.action_mailer.default_url_options[:host] (APP_HOST) is the fallback
  # used by Devise's account-claim and password-reset mail. If they disagree,
  # nothing raises -- customers simply receive links to two different hosts, one
  # of which may not resolve.
  #
  # This is most likely to happen during a domain cutover, which is exactly when
  # nobody is watching for it. Note that BOTH settings default to the wholesale
  # subdomain when their environment variables are unset, so an unset variable
  # is a decision, not a neutral state.
  class DomainStatus
    def initialize(env: ENV)
      @env = env
    end

    # The host emailed links fall back to.
    def app_host
      normalize(Rails.application.config.action_mailer.default_url_options&.dig(:host))
    end

    # The host Solidus prefers for order emails.
    def store_url
      store = Spree::Store.default
      return nil if store.nil? || store.new_record?

      normalize(store.url)
    end

    # Whether the environment is pinning these, or letting them fall back to the
    # defaults baked into the code.
    def app_host_from_env? = @env["APP_HOST"].present?
    def store_url_from_env? = @env["STORE_URL"].present?

    # The question worth asking: will every emailed link point to one host?
    def consistent?
      app_host.present? && app_host == store_url
    end

    # True once both settings have moved off the onrender.com fallback, i.e. the
    # cutover has happened. Says nothing about whether DNS actually resolves --
    # that has to be checked from outside the service.
    def cut_over?
      consistent? && !app_host.end_with?(".onrender.com")
    end

    private

    # Operators paste URLs; these settings want bare hosts. Compare like for
    # like so "https://wholesale.example.com/" and "wholesale.example.com" do
    # not read as a mismatch.
    def normalize(value)
      return nil if value.blank?

      value.to_s.strip.sub(%r{\Ahttps?://}, "").chomp("/").downcase.presence
    end
  end
end
