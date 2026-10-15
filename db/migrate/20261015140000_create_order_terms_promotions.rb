# frozen_string_literal: true

# Creates the NEWPORTAL code and the $500 free-shipping promotion on deploy.
#
# These were first left to a manual `bin/rails nsb:import:promotions` in the
# Render shell, which was missed: production showed the minimum order in the
# banner but never the free-shipping line, because the banner reads the live
# promotion and there wasn't one. A migration runs exactly once per database,
# on deploy, with nothing to remember.
#
# Once, not every deploy: if the operator later deletes a promotion in the
# admin, it stays deleted. Nsb::PromotionSeeder also skips any promotion that
# already exists, so a database where the rake task WAS run is left untouched.
# The rake task remains for rebuilding a database from scratch.
class CreateOrderTermsPromotions < ActiveRecord::Migration[8.0]
  def up
    Nsb::PromotionSeeder.new.call
  end

  def down
    # Deliberately nothing: removing promotions that customers may already
    # have used belongs in the admin, not in a rollback.
  end
end
