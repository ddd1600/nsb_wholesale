# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

RSpec.describe Nsb::PhoneNumber do
  describe ".format" do
    it "formats ten digits however they were typed" do
      [
        "8435550134",
        "843-555-0134",
        "843.555.0134",
        "(843)5550134",
        " 843 555 0134 "
      ].each do |input|
        expect(described_class.format(input)).to eq("(843) 555-0134")
      end
    end

    it "drops a leading US country code" do
      expect(described_class.format("+1 (843) 555-0134")).to eq("(843) 555-0134")
      expect(described_class.format("18435550134")).to eq("(843) 555-0134")
    end

    it "leaves anything that is not a ten-digit number alone" do
      # Returned as typed rather than mangled, so the validation can complain
      # about the number the applicant actually entered.
      expect(described_class.format("555-0134")).to eq("555-0134")
      expect(described_class.format("+44 20 7946 0958")).to eq("+44 20 7946 0958")
    end

    it "handles blanks" do
      expect(described_class.format(nil)).to eq("")
      expect(described_class.format("")).to eq("")
    end
  end
end
