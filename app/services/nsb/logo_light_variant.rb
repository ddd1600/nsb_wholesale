# frozen_string_literal: true

require "vips"

module Nsb
  # Recolours the wordmark in a logo so it reads on a dark background.
  #
  # The supplied logo is a green pineapple beside near-black text. On the dark
  # theme the text vanishes. A CSS filter is no good -- anything that lightens
  # the text also drains the fruit -- and inverting is worse.
  #
  # So swap only the pixels that are both dark AND unsaturated. That is the ink
  # of the wordmark; the pineapple is saturated green throughout and survives
  # untouched. Transparent pixels are recoloured too, harmlessly, since their
  # alpha is zero either way.
  class LogoLightVariant
    # Below this brightness, and within this spread between the brightest and
    # darkest channel, a pixel is neutral dark ink rather than brand colour.
    MAX_BRIGHTNESS = 120
    MAX_SATURATION = 40

    # The dark theme's text colour (Tailwind `sand`).
    INK = [ 245, 243, 240 ].freeze

    def initialize(source:, target:, ink: INK)
      @source = Pathname(source)
      @target = Pathname(target)
      @ink = ink
    end

    def call
      image = Vips::Image.new_from_file(@source.to_s)
      raise "#{@source} has no alpha channel; expected a transparent PNG" unless image.has_alpha?

      rgb = image.extract_band(0, n: 3)
      alpha = image[image.bands - 1]

      red, green, blue = rgb[0], rgb[1], rgb[2]
      brightest = red.maxpair(green).maxpair(blue)
      darkest = red.minpair(green).minpair(blue)
      neutral_dark = (brightest < MAX_BRIGHTNESS) & ((brightest - darkest) < MAX_SATURATION)

      neutral_dark.ifthenelse(@ink, rgb).bandjoin(alpha).write_to_file(@target.to_s)
      @target
    end
  end
end
