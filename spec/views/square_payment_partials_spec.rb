# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# Solidus derives five partial paths from PaymentMethod#partial_name and renders
# them in different places -- checkout, saved sources, admin form, admin view and
# the API. Only the checkout one existed, so opening a payment in the admin blew
# up with MissingTemplate on a real order.
#
# Asserting the files exist is deliberately cheap and blunt: the failure mode is
# a 500 in a place nobody looks until they are mid-refund on a real order.
RSpec.describe "Square payment method partials" do
  let(:partial_name) { Spree::PaymentMethod::SquareCreditCard.new.partial_name }

  it "uses the partial name the views are written for" do
    expect(partial_name).to eq("square")
  end

  {
    "checkout form" => "app/views/checkouts/payment/_%s.html.erb",
    "saved source" => "app/views/checkouts/existing_payment/_%s.html.erb",
    "admin source form" => "app/views/spree/admin/payments/source_forms/_%s.html.erb",
    "admin source view" => "app/views/spree/admin/payments/source_views/_%s.html.erb",
    "api source view" => "app/views/spree/api/payments/source_views/_%s.json.jbuilder"
  }.each do |description, template|
    it "has a #{description} partial" do
      path = Rails.root.join(format(template, "square"))
      expect(path).to exist, "missing #{path.relative_path_from(Rails.root)}"
    end
  end

  it "never renders card numbers in any of them" do
    Dir[Rails.root.join("app/views/**/_square.html.erb")].each do |file|
      contents = File.read(file)
      expect(contents).not_to match(/\[number\]|verification_value|card_number/),
        "#{file} looks like it renders raw card fields"
    end
  end
end
