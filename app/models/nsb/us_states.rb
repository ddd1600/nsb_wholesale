# frozen_string_literal: true

require "carmen"

module Nsb
  # The states a retail license can be issued in, for the application form.
  #
  # From Carmen, not from Spree::State. Solidus's states are database rows, and a
  # validation that reads them fails closed: on a database where they were never
  # seeded -- a fresh test run, a restored dump -- the list comes back empty and
  # every application is rejected for naming a state that "does not exist". A
  # gem-backed constant cannot do that.
  #
  # APO/FPO military codes are dropped: they are mailing designations, not
  # licensing jurisdictions. Territories stay, because a licensed retailer in
  # Puerto Rico is a real applicant.
  module UsStates
    EXCLUDED_TYPES = %w[apo].freeze

    module_function

    # [[name, code]] for a select, alphabetical by name.
    def options
      cached[:options]
    end

    def codes
      cached[:codes]
    end

    def name_for(code)
      cached[:names][code.to_s.strip.upcase]
    end

    def cached
      @cached ||= build
    end

    def reset!
      @cached = nil
    end

    def build
      subregions = Carmen::Country.coded("US").subregions
        .reject { |region| EXCLUDED_TYPES.include?(region.type) }
        .sort_by(&:name)

      {
        options: subregions.map { |region| [ region.name, region.code ] },
        codes: subregions.map(&:code).freeze,
        names: subregions.to_h { |region| [ region.code, region.name ] }
      }
    end
  end
end
