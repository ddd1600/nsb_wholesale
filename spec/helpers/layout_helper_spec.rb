# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

RSpec.describe LayoutHelper, type: :helper do
  let!(:store) { create(:store, default: true, url: "wholesale.example.com") }

  before { allow(helper).to receive(:current_store).and_return(store) }

  def canonical_for(path, params = {})
    controller.request.path_parameters = { controller: "products", action: "show" }.merge(params)
    allow(helper.request).to receive(:path).and_return(path)
    allow(helper).to receive(:params).and_return(ActionController::Parameters.new(params))
    helper.simple_canonical_tag
  end

  it "strips a format extension from the canonical path" do
    expect(canonical_for("/products/tincture.json", format: "json"))
      .to include("/products/tincture")
  end

  it "strips a trailing slash" do
    expect(canonical_for("/products/", {})).to include("wholesale.example.com/products")
  end

  # Regression: params[:format] used to be interpolated into a Regexp, so a
  # crafted format could make the pattern pathological on every page render.
  it "does not build a regular expression from the format parameter" do
    evil = "(a+)+$" * 40

    expect {
      Timeout.timeout(5) { canonical_for("/products/tincture", format: evil) }
    }.not_to raise_error
  end

  it "leaves the path alone when the format does not match the extension" do
    expect(canonical_for("/products/tincture", format: "html"))
      .to include("/products/tincture")
  end
end
