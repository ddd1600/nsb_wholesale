# frozen_string_literal: true

namespace :nsb do
  namespace :brand do
    desc "Regenerate the dark-theme logo from the colour original (safe to re-run)"
    task light_variant: :environment do
      brand = Rails.root.join("app/assets/images/brand")
      target = Nsb::LogoLightVariant.new(
        source: brand.join("nsb_logo_horizontal.png"),
        target: brand.join("nsb_logo_horizontal_light.png")
      ).call

      puts "wrote #{target.relative_path_from(Rails.root)}"
      puts "Check it against a dark background before committing -- it is a"
      puts "generated approximation of a brand asset, not the designer's file."
    end
  end
end
