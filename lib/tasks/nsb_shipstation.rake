# frozen_string_literal: true

namespace :nsb do
  namespace :shipstation do
    desc "Check ShipStation credentials work (read-only, creates nothing)"
    task check: :environment do
      config = Nsb::Shipstation::Configuration.new

      unless config.configured?
        abort "Not configured. Set SHIPSTATION_API_KEY and SHIPSTATION_API_SECRET."
      end

      require "net/http"
      key, secret = config.credentials!
      uri = URI.join(config.base_url, "/accounts/listtags")
      request = Net::HTTP::Get.new(uri)
      request.basic_auth(key, secret)

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }

      if response.code.to_i == 200
        puts "ShipStation credentials OK (#{config.base_url})"
        puts "pushes enabled: #{config.enabled?}"
      else
        abort "ShipStation rejected the credentials (HTTP #{response.code}): #{response.body.to_s.first(200)}"
      end
    end

    desc "List ShipStation stores and their IDs, to pick one for SHIPSTATION_STORE_ID"
    task stores: :environment do
      require "net/http"
      config = Nsb::Shipstation::Configuration.new
      key, secret = config.credentials!

      uri = URI.join(config.base_url, "/stores")
      request = Net::HTTP::Get.new(uri)
      request.basic_auth(key, secret)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }

      abort "ShipStation returned HTTP #{response.code}: #{response.body.to_s.first(200)}" unless response.code.to_i == 200

      stores = JSON.parse(response.body)
      puts format("%-10s %-30s %s", "ID", "NAME", "ACTIVE")
      stores.each do |store|
        puts format("%-10s %-30s %s", store["storeId"], store["storeName"].to_s.first(30), store["active"])
      end
      puts
      puts "Set SHIPSTATION_STORE_ID to the id of the store these orders should land in."
      puts "Without it, ShipStation files API-created orders under Manual Orders."
    end

    desc "Re-push orders whose ShipStation push failed. Usage: rake 'nsb:shipstation:repush[R123456789]' or omit for all failed"
    task :repush, [:order_number] => :environment do |_task, args|
      orders =
        if args[:order_number].present?
          Spree::Order.where(number: args[:order_number])
        else
          # Anything not successfully pushed. Uses the status the job records on
          # admin_metadata, so this is the recovery path for a ShipStation
          # outage that outlasted the job's retries.
          Spree::Order.complete.select do |order|
            state = order.admin_metadata&.dig("shipstation", "state")
            state.nil? || %w[failed retrying skipped].include?(state)
          end
        end

      if orders.none?
        puts "Nothing to re-push."
        next
      end

      puts "re-pushing #{orders.count} order(s)"

      # perform_now, not perform_later. This is a manual recovery command run by
      # a human at a terminal: they should see the outcome immediately, and with
      # the async queue adapter a rake process can exit before an enqueued job
      # ever runs -- silently doing nothing.
      failures = 0
      orders.each do |order|
        print "  #{order.number}... "
        begin
          Nsb::PushOrderToShipstationJob.perform_now(order)
          state = order.reload.admin_metadata&.dig("shipstation", "state")
          id = order.admin_metadata&.dig("shipstation", "shipstation_order_id")
          puts state == "pushed" ? "pushed (ShipStation id #{id})" : "#{state}"
          failures += 1 unless state == "pushed"
        rescue => error
          puts "FAILED: #{error.class}: #{error.message}"
          failures += 1
        end
      end

      abort "#{failures} of #{orders.count} did not push" if failures.positive?
      puts "All pushed."
    end

    desc "Show ShipStation push status for recent orders"
    task status: :environment do
      Spree::Order.complete.order(completed_at: :desc).limit(20).each do |order|
        status = order.admin_metadata&.dig("shipstation") || {}
        state = status["state"] || "(never pushed)"
        detail = status["shipstation_order_id"] || status["error"]
        puts format("%-14s %-10s %s", order.number, state, detail.to_s.first(60))
      end
    end
  end
end
