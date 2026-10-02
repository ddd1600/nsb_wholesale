# frozen_string_literal: true

require 'solidus_starter_frontend_spec_helper'

# The Delta 8 Gummies page is about half of all sales, and is sold in two pack
# sizes as Solidus variants. These run in a real browser because every failure
# they guard against is JavaScript: the picker must put the pack size the
# customer chose into the cart, and show its price, however they reached the
# page -- including by clicking through the site, which Turbo turns into a
# page swap that never fires DOMContentLoaded.
RSpec.describe 'Pack size picker', type: :system, js: true do
  let!(:store) { create(:store) }
  let!(:user) { create(:user, password: 'secret123', password_confirmation: 'secret123') }
  let(:pack_size) { create(:option_type, name: 'pack_size', presentation: 'Pack Size', position: 1) }
  let(:flavor) { create(:option_type, name: 'flavor', presentation: 'Flavor', position: 2) }
  let(:thirty) { create(:option_value, option_type: pack_size, name: '30ct', presentation: '30ct') }
  let(:ten) { create(:option_value, option_type: pack_size, name: '10ct', presentation: '10ct') }
  let(:blue) { create(:option_value, option_type: flavor, name: 'blue-raspberry', presentation: 'Blue Raspberry') }
  let(:straw) { create(:option_value, option_type: flavor, name: 'strawberry', presentation: 'Strawberry') }
  let!(:product) do
    create(:product, name: 'Delta 8 Gummies', price: 30, option_types: [pack_size, flavor]).tap do |p|
      [[thirty, 30, '30Ct'], [ten, 10, '10Ct']].each do |size, price, code|
        [[blue, 'BlueRaspberry'], [straw, 'Strawberry']].each do |taste, suffix|
          create(:variant, product: p, sku: "E-D8Gummies#{code}-#{suffix}", price: price, option_values: [size, taste])
        end
      end
    end
  end

  before do
    visit login_path
    fill_in 'Email', with: user.email
    fill_in 'Password:', with: 'secret123'
    click_button 'Login'
    expect(page).to have_text 'Logged in successfully'
  end

  def cart_skus
    Spree::Order.last.line_items.map { |li| [li.variant.sku, li.quantity] }
  end

  shared_examples 'a working picker' do
    it 'adds the chosen pack size, and the button price follows it' do
      expect(page).to have_css('#cta_price', text: '$30.00')

      find('label', text: '10ct').click
      expect(page).to have_css('#cta_price', text: '$10.00')

      fill_in 'quantity', with: '3'
      find('#quantity').send_keys(:tab)
      expect(page).to have_css('#cta_price', text: '$30.00')

      click_button 'add-to-cart-button'
      expect(page).to have_content('Shopping Cart')
      expect(cart_skus).to eq([['E-D8Gummies10Ct-BlueRaspberry', 3]])
    end

    it 'adds the chosen flavour as well as the chosen size' do
      find('label', text: '10ct').click
      find('label', text: 'Strawberry').click
      expect(page).to have_css('#selected-flavor', text: 'Strawberry')
      expect(page).to have_css('#cta_price', text: '$10.00')

      click_button 'add-to-cart-button'
      expect(page).to have_content('Shopping Cart')
      expect(cart_skus).to eq([['E-D8Gummies10Ct-Strawberry', 1]])
    end

    it 'shows which pack size is selected, and its price in the header' do
      expect(page).to have_css('#selected-pack_size', text: '30ct')
      find('label', text: '10ct').click
      expect(page).to have_css('#selected-pack_size', text: '10ct')
      expect(page).to have_css("[data-js='price']", text: '$10.00')
      expect(find('input[data-presentation="10ct"]', visible: :all)).to be_checked
    end
  end

  context 'when the product page is loaded directly' do
    before { visit product_path(product) }

    it_behaves_like 'a working picker'
  end

  context 'when the customer clicks through to it (Turbo navigation)' do
    before do
      visit products_path
      click_link 'Delta 8 Gummies', match: :first
      expect(page).to have_css('h1', text: 'Delta 8 Gummies')
    end

    it_behaves_like 'a working picker'
  end
end
