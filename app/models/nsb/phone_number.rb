# frozen_string_literal: true

module Nsb
  # Formatting for the US phone numbers on the wholesale application form.
  #
  # The same rule runs in two places on purpose: this, and the Stimulus
  # controller that formats the field as it is typed. The browser one is what the
  # applicant sees; this one is what makes it true, because a form can always be
  # submitted without it.
  module PhoneNumber
    FORMATTED = /\A\(\d{3}\) \d{3}-\d{4}\z/

    module_function

    # "8435551234", "843-555-1234", "+1 (843) 555 1234" -> "(843) 555-1234".
    # Anything that is not a ten-digit US number is returned as it came in, for
    # the validation to reject with a message about the number rather than
    # silently mangling what someone typed.
    def format(value)
      digits = value.to_s.gsub(/\D/, "")
      digits = digits[1..] if digits.length == 11 && digits.start_with?("1")
      return value.to_s.strip unless digits.length == 10

      "(#{digits[0, 3]}) #{digits[3, 3]}-#{digits[6, 4]}"
    end

    def formatted?(value) = FORMATTED.match?(value.to_s)
  end
end
