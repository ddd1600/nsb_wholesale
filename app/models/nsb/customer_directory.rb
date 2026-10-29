# frozen_string_literal: true

module Nsb
  # The customer list behind the admin's "Place an order" page.
  #
  # Most customers migrated from B2BWave have no saved address, so their
  # business name lives only in admin_metadata["b2bwave"] (see
  # Nsb::CustomerImporter). Searching addresses alone found almost nobody.
  #
  # Ordered by most recent order first, counting both portal orders and the
  # last order B2BWave recorded ("latest_order_submitted_at"). Customers who
  # have never ordered follow, A-Z by business name.
  #
  # Built in Ruby rather than SQL: ~360 customers, a handful of admin page
  # views a day, and the B2BWave date is a "MM/DD/YYYY HH:MM" string in JSON.
  class CustomerDirectory
    Entry = Struct.new(:user, :business_name, :contact_name, :last_order_on, :last_order_source,
      keyword_init: true)

    def initialize(query: nil)
      @query = query.to_s.strip
    end

    def entries
      list = customers.map { |user| entry_for(user) }
      list = list.select { |entry| matches?(entry) } if @query.present?

      ordered, never = list.partition(&:last_order_on)
      ordered.sort_by { |entry| [ -entry.last_order_on.jd, entry.business_name.downcase ] } +
        never.sort_by { |entry| entry.business_name.downcase }
    end

    # Loose enough that "back 2 nature" finds "Back To Nature": case,
    # punctuation and spacing are ignored, and "2"/"to" and "&"/"and" are
    # treated alike.
    def self.normalize(text)
      text.to_s.downcase
        .gsub("&", " and ")
        .gsub(/\b2\b/, " to ")
        .gsub(/[^a-z0-9]/, "")
    end

    private

    def customers
      admin_ids = Spree::Role.find_by(name: "admin")&.users&.pluck(:id) || []
      Spree.user_class.where.not(id: admin_ids).includes(bill_address: [], addresses: [])
    end

    def entry_for(user)
      b2bwave = (user.admin_metadata || {}).fetch("b2bwave", {})
      address = user.bill_address || user.addresses.first

      portal_date = portal_last_orders[user.id]&.to_date
      b2bwave_date = parse_b2bwave_date(b2bwave["latest_order_submitted_at"])
      last_order_on, source =
        if portal_date && (b2bwave_date.nil? || portal_date >= b2bwave_date)
          [ portal_date, :portal ]
        elsif b2bwave_date
          [ b2bwave_date, :b2bwave ]
        end

      Entry.new(
        user: user,
        business_name: b2bwave["company_name"].presence || address&.company.presence || user.email,
        contact_name: b2bwave["name"].presence || address&.name,
        last_order_on: last_order_on,
        last_order_source: source
      )
    end

    def matches?(entry)
      needle = self.class.normalize(@query)
      [ entry.business_name, entry.contact_name, entry.user.email ].any? do |field|
        self.class.normalize(field).include?(needle)
      end
    end

    def portal_last_orders
      @portal_last_orders ||= Spree::Order.complete.group(:user_id).maximum(:completed_at)
    end

    def parse_b2bwave_date(value)
      Date.strptime(value, "%m/%d/%Y") if value.present?
    rescue Date::Error
      nil
    end
  end
end
