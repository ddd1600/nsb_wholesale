# frozen_string_literal: true

# The active_storage_db gem registers "DB" as a GLOBAL inflection acronym
# (its config/initializers/inflections.rb). That changes how Rails camelizes
# every db_* filename in the app, so Zeitwerk starts expecting Solidus's
# app/models/spree/validations/db_maximum_length_validator.rb to define
# Spree::Validations::DBMaximumLengthValidator. It defines
# DbMaximumLengthValidator, so every page rendering a taxon filter blew up with
# "uninitialized constant".
#
# The gem needs the acronym for its own ActiveStorageDB constants, so rather
# than strip it we pin the one file it collides with. A sweep of solidus_core,
# solidus_backend, solidus_api and solidus_auth_devise found this to be the only
# db_*.rb in any autoload path -- re-check if that ever changes.
Rails.autoloaders.main.inflector.inflect(
  "db_maximum_length_validator" => "DbMaximumLengthValidator"
)
