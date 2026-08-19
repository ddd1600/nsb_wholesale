require_relative "boot"
require_relative "site_password_gate"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module NsbWholesale
  class Application < Rails::Application
    if defined?(FactoryBotRails)
      initializer after: "factory_bot.set_factory_paths" do
        require 'spree/testing_support/factory_bot'

        # The paths for Solidus' core factories.
        solidus_paths = Spree::TestingSupport::FactoryBot.definition_file_paths

        # Optional: Any factories you want to require from extensions.
        extension_paths = [
          # MySolidusExtension::Engine.root.join("lib/my_solidus_extension/testing_support/factories"),
          # or individually:
          # MySolidusExtension::Engine.root.join("lib/my_solidus_extension/testing_support/factories/resource.rb"),
        ]

        # Your application's own factories.
        app_paths = [
          Rails.root.join('spec/factories'),
        ]

        FactoryBot.definition_file_paths = solidus_paths + extension_paths + app_paths
      end
    end
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # New South Botanicals operates from South Carolina. Without this, orders and
    # emails render in UTC, so an order placed at 8pm Tuesday reads as Wednesday
    # to both the customer and the operator.
    #
    # Only display is affected: Active Record still stores timestamps in UTC
    # (default_timezone is untouched), so existing data needs no migration.
    config.time_zone = "Eastern Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Temporary password gate for the whole site. Active only when
    # SITE_PASSWORD is set, so development and test are unaffected. Inserted at
    # the top of the stack so it also covers /admin, which does not inherit from
    # this app's ApplicationController.
    config.middleware.insert_before 0, SitePasswordGate

    # Don't generate system test files.
    config.generators.system_tests = nil

    # sassc-rails (pulled in by solidus_backend) defaults css_compressor to
    # :sass, which cannot parse Tailwind's modern colour syntax, e.g.
    # `rgb(245 243 240/var(--tw-bg-opacity))`. Any page rendering the Tailwind
    # bundle then raises SassC::SyntaxError.
    #
    # Set here rather than per-environment so it also covers asset
    # precompilation on deploy. Tailwind already emits minified CSS in
    # production, so no compressor is needed.
    #
    # The Solidus starter frontend template tries to set this in
    # config/environments/test.rb, but anchors the insert to a line that does
    # not exist in Rails 8, so its edit silently no-ops.
    config.assets.css_compressor = nil
  end
end
