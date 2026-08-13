source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.5", ">= 8.0.5.1"
# Sprockets, NOT Propshaft (the Rails 8 default). Solidus requires it:
# solidus_backend depends on sprockets-rails/sassc-rails, and the Solidus
# starter frontend template uses Sprockets-only APIs (config.assets.precompile,
# require_tree). Propshaft has no equivalent, so the app cannot boot with it.
gem "sprockets-rails"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

# Solidus: storefront, catalog, cart, checkout and admin. See CLAUDE.md — the
# store is NOT hand-rolled; products/orders/users/addresses all come from here.
gem "solidus", "~> 4.7.0"
# Devise-backed authentication for Solidus users (wholesale customers + admins).
gem "solidus_auth_devise", "~> 2.6"

# Square's official Ruby SDK. Square is the payment processor for this store --
# see CLAUDE.md. Do not add Stripe/Braintree/PayPal alternatives.
gem "square.rb", "~> 46.0", require: "square"

# Active Storage service that keeps uploaded files in PostgreSQL instead of on
# disk. Render wipes a service's filesystem on every deploy, and its persistent
# disks cannot be reached from one-off jobs (which is how nsb:import:catalog
# runs). Keeping blobs in the database means a single pg_dump backs up the
# catalog images too. Viable here only because the catalog is ~6MB.
gem "active_storage_db"

group :development, :test do
  # NOTE: rspec-rails, factory_bot, capybara et al. are added by the Solidus
  # starter frontend template. Do not declare them here — Bundler raises on a
  # duplicate gem entry.

  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Captures outbound mail instead of sending it, keeping production SMTP
  # credentials unreachable from development (EMAIL_SETUP.md).
  #
  # The _web variant on purpose: plain letter_opener launches the message in the
  # browser the moment it is delivered, which hijacked the tab mid-checkout and
  # replaced the order confirmation page with the email. This one just collects
  # messages at /letter_opener for you to read when you want to.
  gem "letter_opener_web"
end
gem "responders"
gem "solidus_support", ">= 0.12.0"
gem "view_component", "~> 3.0"
gem "tailwindcss-rails", "~> 3.0"

group :test do
  gem "capybara"
  gem "selenium-webdriver"
  gem "capybara-screenshot", "~> 1.0"
  gem "database_cleaner", "~> 2.0"
end

group :development, :test do
  gem "rspec-rails"
  gem "rails-controller-testing", "~> 1.0.5"
  gem "rspec-activemodel-mocks", "~> 1.1.0"
  gem "factory_bot", ">= 4.8"
  gem "factory_bot_rails"
  gem "ffaker", "~> 2.13"
  gem "rubocop", "~> 1.0"
  gem "rubocop-performance", "~> 1.5"
  gem "rubocop-rails", "~> 2.3"
  gem "rubocop-rspec", "~> 3.0"
end
