# frozen_string_literal: true

require 'solidus_starter_frontend_spec_helper'

RSpec.describe 'Cart line item permissions', type: :request do
  let(:order) { create(:order, user: nil, store: store) }
  let!(:store) { create(:store) }
  let(:variant) { create(:variant) }

  context 'when an order exists in the cookies.signed', with_guest_session: true do
    before { order.update(guest_token: nil) }

    context '#create' do
      # Still refused, and now refused earlier: Nsb::RequiresWholesaleAccount
      # turns away anonymous requests before Solidus's ability check on the
      # mismatched guest token is reached, so the destination is the welcome
      # page rather than the login form. The property under test -- that an
      # anonymous visitor cannot add to an order that is not theirs -- is
      # unchanged.
      it 'refuses an anonymous request, before the ability check is reached' do
        post cart_line_items_path, params: { variant_id: variant.id }
        expect(response).to redirect_to(welcome_path)
      end
    end
  end
end
