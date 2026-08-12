# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# Guards config/initializers/zeitwerk.rb. The active_storage_db gem registers
# "DB" as a global inflection acronym, which makes Zeitwerk expect Solidus's
# db_maximum_length_validator.rb to define DBMaximumLengthValidator. Without the
# override every storefront page that renders taxon filters 500s.
RSpec.describe "Zeitwerk inflections" do
  it "resolves Solidus's Db-prefixed validator despite the DB acronym" do
    expect { Spree::Validations::DbMaximumLengthValidator }.not_to raise_error
  end

  it "still resolves the gem's own DB-acronym constants" do
    expect(ActiveStorageDB::File).to be < ActiveRecord::Base
  end
end
