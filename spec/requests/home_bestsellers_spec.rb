# frozen_string_literal: true

require 'solidus_starter_frontend_spec_helper'

# The homepage is the demand ranking (see Nsb::OrderFrequencyRanking). These
# specs render it for real rather than stubbing the searcher, because the failure
# mode worth catching is a partial that raises, not a wrong query.
RSpec.describe 'Homepage demand ranking', type: :request, with_signed_in_user: true do
  let(:user) { create(:user) }

  # Enough to fill the podium (3), the spotlight grid (9) and spill into the
  # long-tail list, so every partial on the page actually renders. Units descend
  # with rank; revenue ascends, so the two metrics order the list oppositely.
  # Zero-padded: "Ranked product 1" would be a substring of "Ranked product 12",
  # so an unpadded name cannot be asserted absent from the rendered page.
  let(:ranked_names) { (1..14).map { |n| format('Ranked product %02d', n) } }

  let(:fixture) do
    {
      source_file: 'orders_test.xlsx',
      total_orders: 100,
      total_line_items: 250,
      first_order_date: '2021-10-28',
      last_order_date: '2026-08-04',
      products: ranked_names.each_with_index.map do |name, index|
        {
          rank: index + 1, sku: "SKU-#{index}", name: name, orders: 50 - index,
          units: (100 - index * 5).to_f, revenue: (100 + index * 5).to_f, customers: 3,
          first_ordered: '2021-11-16', last_ordered: '2026-07-31'
        }
      end
    }
  end

  let(:data_file) do
    file = Tempfile.new([ 'ranking', '.json' ])
    file.write(fixture.to_json)
    file.flush
    file
  end

  before do
    stub_const('Nsb::OrderFrequencyRanking::DATA_PATH', Pathname.new(data_file.path))
    ranked_names.each_with_index { |name, index| create(:product, name: name, sku: "SKU-#{index}") }
    create(:product, name: 'Never ordered product', sku: 'SKU-NEW')
  end

  it 'renders successfully' do
    get root_path
    expect(response.status).to eq(200)
  end

  it 'defaults to ranking by units sold' do
    get root_path
    expect(response.body).to include('Ranked by units sold')
    expect(response.body).to include('of units sold')
  end

  it 'ranks by dollar sales when the selector is used' do
    get root_path(rank_by: 'sales')
    expect(response.body).to include('Ranked by dollar sales')
    expect(response.body).to include('of sales')
  end

  it 'puts the highest-units product first by default' do
    get root_path
    podium = response.body[/Most-ordered products.*?Also ordered often/m]
    expect(podium).to include('Ranked product 01')
    expect(podium).not_to include('Ranked product 14')
  end

  it 'reverses the leader when ranking by dollar sales' do
    get root_path(rank_by: 'sales')
    podium = response.body[/Most-ordered products.*?Also ordered often/m]
    expect(podium).to include('Ranked product 14')
    expect(podium).not_to include('Ranked product 01')
  end

  it 'falls back to units for an unrecognised metric' do
    get root_path(rank_by: 'nonsense')
    expect(response.body).to include('Ranked by units sold')
  end

  it 'hides catalog products with no order history' do
    get root_path
    expect(response.body).not_to include('Never ordered product')
  end

  it 'never states a raw order count' do
    get root_path
    # The old design printed "237 orders" throughout. Percentages only now.
    expect(response.body).not_to match(/\d+\s+orders?\b/)
    expect(response.body).not_to include('Ranked by your order history')
  end

  it 'offers both metrics as links' do
    get root_path
    expect(response.body).to include('Units sold')
    expect(response.body).to include('Dollar sales')
  end
end
