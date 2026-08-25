# frozen_string_literal: true

require 'solidus_starter_frontend_spec_helper'

# The homepage is the demand ranking (see Nsb::DemandRanking). These specs render
# it for real rather than stubbing the searcher, because the failure mode worth
# catching is a partial that raises, not a wrong query.
RSpec.describe 'Homepage demand ranking', type: :request, with_signed_in_user: true do
  let(:user) { create(:user) }

  # Enough to fill the podium (3), the spotlight grid (9) and spill into the
  # long-tail list, so every partial on the page actually renders. Zero-padded:
  # "product 1" would be a substring of "product 12", so an unpadded name cannot
  # be asserted absent from the rendered page.
  let(:names) { (1..14).map { |n| format('Ranked product %02d', n) } }

  # Wholesale counts down, retail counts up, so the two channels put opposite
  # products on the podium.
  def payload(channel:, ascending:)
    products = names.each_with_index.map do |name, index|
      position = ascending ? index : names.size - 1 - index
      { rank: index + 1, sku: "SKU-#{index}", name: name,
        units: (10 + position * 10).to_f, sales: (100 + position * 100).to_f }
    end
    base = { channel: channel.to_s, total_units: 10_000.0, total_sales: 100_000.0, products: products }
    if channel == :wholesale
      base.merge(first_order_date: '2021-10-28', last_order_date: '2026-08-04')
    else
      base.merge(first_sale_date: '2020-07-10', last_sale_date: '2026-08-24')
    end
  end

  let(:data_dir) { Pathname.new(Dir.mktmpdir) }

  before do
    data_dir.join('product_order_frequency.json').write(payload(channel: :wholesale, ascending: false).to_json)
    data_dir.join('product_retail_frequency.json').write(payload(channel: :retail, ascending: true).to_json)
    stub_const('Nsb::DemandRanking::DATA_DIR', data_dir)

    names.each_with_index { |name, index| create(:product, name: name, sku: "SKU-#{index}") }
    create(:product, name: 'Never ordered product', sku: 'SKU-NEW')
  end

  after { FileUtils.remove_entry(data_dir) }

  def podium
    response.body[/Most-ordered products.*?Also ordered often/m]
  end

  it 'renders successfully' do
    get root_path
    expect(response.status).to eq(200)
  end

  it 'defaults to wholesale, ranked by units sold' do
    get root_path
    expect(response.body).to include('Ranked by units sold')
    expect(response.body).to include('of units sold')
    expect(podium).to include('Ranked product 01')
  end

  it 'switches to retail, which ranks the opposite way' do
    get root_path(channel: 'retail')
    expect(podium).to include('Ranked product 14')
    expect(podium).not_to include('Ranked product 01')
  end

  it 'switches to dollar sales within a channel' do
    get root_path(rank_by: 'sales')
    expect(response.body).to include('Ranked by dollar sales')
    expect(response.body).to include('of sales')
  end

  it 'keeps channel and metric independent' do
    get root_path(channel: 'retail', rank_by: 'sales')
    expect(response.body).to include('Ranked by dollar sales')
    expect(podium).to include('Ranked product 14')
  end

  it 'says the percentages belong to one channel only' do
    get root_path(channel: 'retail')
    expect(response.body).to include('shares of')
    expect(response.body).to include('counted separately')
  end

  it 'falls back to the defaults for unrecognised parameters' do
    get root_path(channel: 'nonsense', rank_by: 'nonsense')
    expect(response.body).to include('Ranked by units sold')
    expect(podium).to include('Ranked product 01')
  end

  it 'hides catalog products with no history on the channel' do
    get root_path
    expect(response.body).not_to include('Never ordered product')
  end

  it 'hides discontinued products' do
    Spree::Product.joins(:master).find_by('spree_variants.sku' => 'SKU-0').update!(discontinue_on: 1.day.ago)

    get root_path

    expect(response.body).not_to include('Ranked product 01')
  end

  it 'never states a raw order count' do
    get root_path
    # The first design printed "237 orders" throughout. Percentages only now.
    expect(response.body).not_to match(/\d+\s+orders?\b/)
  end

  it 'offers both channels and both metrics' do
    get root_path
    expect(response.body).to include('Wholesale').and include('Retail')
    expect(response.body).to include('Units sold').and include('Dollar sales')
  end
end
