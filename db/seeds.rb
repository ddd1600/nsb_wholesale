# Seeds must be idempotent: db:prepare runs them when it creates the schema, and
# `bin/rails db:seed` can be run again at any time.
#
# On Render this is the only hook that runs automatically on a fresh database --
# the free plan has no shell, so there is nowhere to run the import tasks by
# hand. Everything safe and re-runnable therefore happens here.
#
# Deliberately NOT here: the customer import. db/import_data/customers.json
# holds PII for ~360 wholesale customers, is gitignored, and is not in the
# Docker image. Run that once from a trusted machine against the target
# database:
#
#   DATABASE_URL=<render external connection string> bin/rails nsb:import:customers

# Solidus's own seeds: countries, states, roles, zones, shipping categories, and
# the admin user (from ADMIN_EMAIL / ADMIN_PASSWORD).
Spree::Core::Engine.load_seed
Spree::Auth::Engine.load_seed

# Store identity: name, url and the from-address on outbound email. Without this
# the store is "Sample Store" at example.com, which is what customers would see
# in their inbox.
Nsb::StoreConfigurator.new.call

# Refund reasons beyond Solidus's single "Return processing".
Nsb::RefundReasonSeeder.new.call

# The catalog: 41 products and 30 images, read from the committed files in
# db/import_data. No network access needed -- deliberately, since we are
# migrating off B2BWave and its CDN may not outlive the migration.
catalog = Nsb::CatalogImporter.new.call
abort "catalog import failed: #{catalog.failures.inspect}" if catalog.failures.any?

# Shipping methods, from the rows B2BWave modelled as products.
shipping = Nsb::ShippingMethodImporter.new.call
abort "shipping import failed: #{shipping.failures.inspect}" if shipping.failures.any?

# The Square payment method. Inactive-looking until SQUARE_* env vars are set;
# the checkout partial says so explicitly rather than failing silently.
Spree::PaymentMethod::SquareCreditCard.find_or_initialize_by(
  type: "Spree::PaymentMethod::SquareCreditCard"
).tap do |method|
  method.name = "Credit Card"
  method.description = "Pay securely by card."
  method.active = true
  method.available_to_users = true
  method.available_to_admin = true
  method.auto_capture = true
  method.save!
end

puts "seeds complete: #{Spree::Product.count} products, " \
     "#{Spree::ShippingMethod.count} shipping methods, " \
     "#{Spree::RefundReason.count} refund reasons"
