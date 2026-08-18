# frozen_string_literal: true

module Nsb
  module Shipstation
    # ShipStation API V1 credentials and endpoint, read only from ENV.
    #
    # V1 rather than V2 deliberately: V1's POST /orders/createorder pushes an
    # order into the Orders tab for the operator to rate-shop and ship by hand,
    # which is how this business actually works. V2 is shipment-centric and
    # would mean the portal choosing carriers and buying labels. V1 is
    # deprecated with no removal date announced -- see task notes.
    #
    # Required:
    #   SHIPSTATION_API_KEY    - from ShipStation Settings > Account > API Settings
    #   SHIPSTATION_API_SECRET
    # Optional:
    #   SHIPSTATION_ENABLED    - set to "false" to stop pushing without removing
    #                            credentials, e.g. while debugging
    class Configuration
      BASE_URL = "https://ssapi.shipstation.com"

      class MissingCredentials < StandardError; end

      def api_key = ENV["SHIPSTATION_API_KEY"].presence
      def api_secret = ENV["SHIPSTATION_API_SECRET"].presence

      # Which ShipStation store the orders are filed under. Without it,
      # ShipStation puts API-created orders in "Manual Orders" alongside
      # anything keyed in by hand -- this account has a dedicated "Wholesale
      # Orders" store, which is where they belong. Find the id with:
      #   bin/rails nsb:shipstation:stores
      def store_id
        value = ENV["SHIPSTATION_STORE_ID"].presence
        value&.to_i
      end

      def configured?
        api_key.present? && api_secret.present?
      end

      # Lets the operator switch pushes off without deleting credentials.
      def enabled?
        return false unless configured?

        ENV.fetch("SHIPSTATION_ENABLED", "true") != "false"
      end

      def base_url = BASE_URL

      def credentials!
        return [api_key, api_secret] if configured?

        missing = []
        missing << "SHIPSTATION_API_KEY" if api_key.blank?
        missing << "SHIPSTATION_API_SECRET" if api_secret.blank?
        raise MissingCredentials, "ShipStation is not configured - missing #{missing.join(', ')}"
      end
    end
  end
end
