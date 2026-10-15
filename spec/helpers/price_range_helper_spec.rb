# frozen_string_literal: true

require 'solidus_starter_frontend_spec_helper'

# ApplicationHelper#nsb_price_range and friends: listings show the spread of a
# product's pack-size prices, not just the master's.
RSpec.describe ApplicationHelper, type: :helper do
  let(:signed_in) { true }

  before do
    allow(helper).to receive(:show_wholesale_prices?).and_return(signed_in)
    allow(helper).to receive(:current_pricing_options)
      .and_return(Spree::Config.pricing_options_class.new(currency: 'USD'))
  end

  let(:product) { create(:product, price: 12.50) }

  # Spree::Money#to_html wraps the symbol and digits in separate spans, so
  # assert on the text a customer would read.
  def shown = Nokogiri::HTML.fragment(helper.nsb_display_price(product).to_s).text

  def add_variant(price)
    create(:variant, product: product, price: price)
  end

  it 'shows a range when pack sizes are priced differently' do
    add_variant(30)
    add_variant(12.50)

    expect(shown).to eq('$12.50 – $30.00')
  end

  it 'shows one price when every pack size costs the same' do
    add_variant(20)
    add_variant(20)

    expect(shown).to include('$20.00')
    expect(shown).not_to include('–')
  end

  it 'uses the master price for a product with no variants' do
    expect(shown).to include('$12.50')
    expect(shown).not_to include('–')
  end

  context 'when the visitor is not signed in' do
    let(:signed_in) { false }

    it 'shows no price at all' do
      add_variant(30)
      expect(helper.nsb_display_price(product)).to be_nil
    end
  end
end
