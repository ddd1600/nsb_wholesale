# frozen_string_literal: true

require 'solidus_starter_frontend_spec_helper'

RSpec.describe CheckoutSessionsController, type: :controller do
  let(:order) { create(:order_with_line_items, email: nil, user: nil, guest_token: token) }
  let(:user)  { build(:user, spree_api_key: 'fake') }
  let(:token) { 'some_token' }
  let(:cookie_token) { token }

  before do
    request.cookie_jar.signed[:guest_token] = cookie_token
    allow(controller).to receive(:current_order) { order }
  end

  context '#new' do
    # The registration step of guest checkout. Closed for the same reason as
    # CheckoutGuestSessionsController: ordering requires a wholesale account.
    # The wholesale gate turns the request away before Solidus's authorize!
    # call is reached, so the ability check this used to assert never runs.
    it 'refuses an anonymous visitor before the ability check' do
      expect(controller).not_to receive(:authorize!)
      request.cookie_jar.signed[:guest_token] = token

      get :new, params: {}

      expect(response).to redirect_to '/welcome'
    end

    it 'lets a signed-in customer through to the ability check' do
      allow(controller).to receive(:spree_current_user) { user }
      expect(controller).to receive(:authorize!).with(:edit, order, token)

      get :new, params: {}
    end
  end
end
