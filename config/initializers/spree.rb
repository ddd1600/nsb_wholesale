# Configure Solidus Preferences
# See http://docs.solidus.io/Spree/AppConfiguration.html for details

# Solidus version defaults for preferences that are not overridden
Spree.load_defaults '4.7.0'

Spree.config do |config|
  # Core:
  # Default currency for new sites
  config.currency = "USD"

  # Inventory is not tracked in this application.
  #
  # The operator manages stock outside the portal. Without this, every product
  # sits at 0 on hand and only sells because each stock item happens to be
  # backorderable -- which works, but means an accidental change to a single
  # stock item silently makes a product unbuyable. Turning tracking off states
  # the intent instead of relying on that side effect.
  config.track_inventory_levels = false

  # When set, product caches are only invalidated when they fall below or rise
  # above the inventory_cache_threshold that is set. Default is to invalidate cache on
  # any inventory changes.
  # config.inventory_cache_threshold = 3

  # Configure adapter for attachments on products and taxons (use ActiveStorageAttachment or PaperclipAttachment)
  config.image_attachment_module = 'Spree::Image::ActiveStorageAttachment'
  config.taxon_attachment_module = 'Spree::Taxon::ActiveStorageAttachment'

  # Uncomment to recalculate cart prices when the cart changes
  # config.recalculate_cart_prices = true

  # Register the ShipStation fulfilment subscriber alongside Solidus's own.
  #
  # It only ENQUEUES a background job when an order is finalized -- the HTTP call
  # to ShipStation never happens inside the order transaction, so an outage
  # there cannot roll back an order Square has already charged.
  config.environment.subscribers << "Nsb::ShipstationSubscriber"

  # Phone is not a required part of an address.
  #
  # Two reasons. First, the B2BWave export has a phone number for only 21 of 360
  # customers, so requiring it would discard 40 otherwise-usable addresses at
  # import and force customers to retype an address we already hold. Second, it
  # is one less mandatory field at checkout for a portal whose whole point is
  # low-friction reordering. ShipStation accepts shipments without a phone.
  config.address_requires_phone = false

  # Defaults
  # Permission Sets:

  # Uncomment and customize the following line to add custom permission sets
  # to a custom users role:
  # config.roles.assign_permissions :role_name, ['Spree::PermissionSets::CustomPermissionSet']

  # Admin:

  # Custom logo for the admin
  # config.admin_interface_logo = "logo/solidus.svg"

  # Payment gateway credentials can be configured statically here and referenced from
  # the admin. They can also be fully configured from the admin.
  #
  # Please note that the example below requires the `solidus_stripe` ~> 5.0 gem
  # in order to work properly (see https://github.com/solidusio-contrib/solidus_stripe).
  #
  # config.static_model_preferences.add(
  #   'SolidusStripe::PaymentMethod',
  #   'solidus_stripe_env_credentials',
  #   api_key: ENV.fetch('SOLIDUS_STRIPE_API_KEY'),
  #   publishable_key: ENV.fetch('SOLIDUS_STRIPE_PUBLISHABLE_KEY'),
  #   test_mode: ENV.fetch('SOLIDUS_STRIPE_API_KEY').start_with?('sk_test_'),
  #   webhook_endpoint_signing_secret: ENV.fetch('SOLIDUS_STRIPE_WEBHOOK_SIGNING_SECRET')
  # )
end

Spree::Backend::Config.configure do |config|
  config.locale = 'en'

  # Uncomment and change the following configuration if you want to add
  # a new menu item:
  #
  # config.menu_items << config.class::MenuItem.new(
  #   label: :my_reports,
  #   icon: 'file-text-o', # see https://fontawesome.com/v4/icons/
  #   url: :my_admin_reports_path,
  #   condition: -> { can?(:admin, MyReports) },
  #   partial: 'spree/admin/shared/my_reports_sub_menu',
  #   match_path: '/reports',
  # )

  # Custom frontend product path
  #
  # config.frontend_product_path = ->(template_context, product) {
  #   template_context.spree.product_path(product)
  # }
end

Spree::Api::Config.configure do |config|
  config.requires_authentication = true
end

# No guest checkout. Wholesale accounts are approval-gated -- existing customers
# claim the account migrated from B2BWave, everyone else applies and waits for a
# person to say yes -- so a guest wholesale customer is a contradiction. Pricing
# is not shown to anyone signed out either, which is most of what checkout is
# for.
#
# Set here as well as enforced by Nsb::RequiresWholesaleAccount, because this is
# the switch a Solidus developer would look for. The controllers that served the
# guest path (CheckoutSessionsController, CheckoutGuestSessionsController) were
# removed on 2026-08-27 rather than left gated and dead.
Spree::Config[:allow_guest_checkout] = false

# The registration step existed to offer "sign in, sign up, or continue as a
# guest" partway through checkout. With guest checkout gone and the storefront
# closed to anonymous visitors, anyone reaching checkout is already signed in,
# so the step has nothing left to ask.
Spree::Auth::Config[:registration_step] = false


# Rules for avoiding to store the current path into session for redirects
# When at least one rule is matched, the request path will not be stored
# in session.
# You can add your custom rules by uncommenting this line and changing
# the class name:
#
# Spree::UserLastUrlStorer.rules << 'Spree::UserLastUrlStorer::Rules::AuthenticationRule'
