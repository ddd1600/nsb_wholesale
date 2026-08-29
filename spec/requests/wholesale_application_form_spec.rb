# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

RSpec.describe "Wholesale application form", type: :request do
  let(:valid_params) do
    {
      business_name: "Coastal Apothecary", contact_name: "Jo Rivera",
      email: "jo@coastalapothecary.test", phone: "843-555-0134",
      address: "12 Front Street, Conway, SC 29526",
      retail_license_state: "SC", retail_license_number: "RL-99881"
    }
  end

  def submit(overrides = {}, extra = {})
    post "/apply", params: { wholesale_application: valid_params.merge(overrides) }.merge(extra)
  end

  describe "required fields" do
    it "marks exactly the seven the operator judges on" do
      get "/apply"

      expect(Nsb::WholesaleApplication::REQUIRED_FIELDS).to contain_exactly(
        :business_name, :contact_name, :email, :phone, :address,
        :retail_license_state, :retail_license_number
      )
    end

    it "accepts an application with the optional questions left blank" do
      expect { submit }.to change(Nsb::WholesaleApplication, :count).by(1)
      expect(response).to redirect_to("/apply/received")
    end

    it "rejects one missing a required field" do
      expect { submit(business_name: "") }.not_to change(Nsb::WholesaleApplication, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "the state dropdown" do
    it "offers states rather than a free-text box" do
      get "/apply"

      expect(response.body).to include("<select", 'value="SC"', "South Carolina")
    end

    it "refuses a state that does not exist" do
      expect { submit(retail_license_state: "ZZ") }.not_to change(Nsb::WholesaleApplication, :count)
    end
  end

  describe "the phone number" do
    it "is stored formatted, however it was typed" do
      submit(phone: "8435550134")

      expect(Nsb::WholesaleApplication.last.phone).to eq("(843) 555-0134")
    end

    it "is rejected when it is not a ten-digit US number" do
      expect { submit(phone: "555-0134") }.not_to change(Nsb::WholesaleApplication, :count)
      expect(response.body).to include("10-digit US phone number")
    end
  end

  describe "the shipping address" do
    it "is optional, because most applicants ship to the business address" do
      expect { submit(shipping_address: "") }.to change(Nsb::WholesaleApplication, :count).by(1)
    end

    it "is recorded when given" do
      submit(shipping_address: "Unit 4, 88 Dock Road, Conway, SC 29526")

      expect(Nsb::WholesaleApplication.last.shipping_address).to include("Dock Road")
    end
  end

  describe "address validation" do
    def google_returns(result)
      allow_any_instance_of(Nsb::AddressValidator).to receive(:call).and_return(result)
    end

    it "asks the applicant to check an address Google could not confirm" do
      google_returns(Nsb::AddressValidator::Result.new(
        status: :suspect, formatted_address: "12 Front St, Conway, SC 29526, USA",
        message: "We could not confirm this address"
      ))

      expect { submit }.not_to change(Nsb::WholesaleApplication, :count)
      expect(response.body).to include("Please check the address you entered")
      expect(response.body).to include("12 Front St, Conway, SC 29526, USA")
    end

    it "does not accept it just because they submitted a second time" do
      # The confirmation used to be a hidden field, so pressing submit again
      # carried it automatically. Typing the useless suggestion back in was
      # enough to get a fake address accepted.
      google_returns(Nsb::AddressValidator::Result.new(status: :suspect, message: "nope"))

      expect { submit }.not_to change(Nsb::WholesaleApplication, :count)
      expect { submit }.not_to change(Nsb::WholesaleApplication, :count)
    end

    it "accepts it once they tick the confirmation box" do
      google_returns(Nsb::AddressValidator::Result.new(status: :suspect, message: "nope"))

      expect { submit({}, addresses_confirmed: "1") }
        .to change(Nsb::WholesaleApplication, :count).by(1)
    end

    it "records the verdict so the operator sees it when deciding" do
      google_returns(Nsb::AddressValidator::Result.new(status: :suspect, message: "nope"))

      submit({}, addresses_confirmed: "1")

      expect(Nsb::WholesaleApplication.last).to be_address_unverified
    end

    it "records a confirmed address as confirmed" do
      google_returns(Nsb::AddressValidator::Result.new(status: :confirmed))

      submit

      expect(Nsb::WholesaleApplication.last.address_verdict).to eq("confirmed")
    end

    it "records 'unchecked' when Google could not be reached, never 'confirmed'" do
      # A blank verdict must never be mistaken for "we checked and it was fine".
      google_returns(Nsb::AddressValidator::Result.new(status: :skipped))

      submit

      expect(Nsb::WholesaleApplication.last.address_verdict).to eq("unchecked")
    end

    # The operator's requirement: an outage or an exhausted quota must never
    # cost an application.
    it "lets the applicant through when the service is unusable" do
      google_returns(Nsb::AddressValidator::Result.new(status: :skipped))

      expect { submit }.to change(Nsb::WholesaleApplication, :count).by(1)
      expect(response).to redirect_to("/apply/received")
    end

    it "lets the applicant through when Google itself is unreachable" do
      # The real validator, with the network failing under it -- not a stub of
      # #call, which would jump over the rescue that does the actual work.
      ClimateControl.modify(GOOGLE_ADDRESS_VALIDATION_API_KEY: "test-key") do
        allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout)

        expect { submit }.to change(Nsb::WholesaleApplication, :count).by(1)
        expect(response).to redirect_to("/apply/received")
      end
    end

    it "lets the applicant through when the quota is exhausted" do
      ClimateControl.modify(GOOGLE_ADDRESS_VALIDATION_API_KEY: "test-key") do
        response_double = instance_double(Net::HTTPResponse, code: "429", body: "quota exceeded")
        allow(response_double).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(Net::HTTP).to receive(:start).and_return(response_double)

        expect { submit }.to change(Nsb::WholesaleApplication, :count).by(1)
        expect(response).to redirect_to("/apply/received")
      end
    end
  end
end
