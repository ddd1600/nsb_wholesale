# frozen_string_literal: true

require 'solidus_starter_frontend_spec_helper'

RSpec.describe CheckoutsController, type: :controller do
  let(:order) { create(:order_with_line_items, email: nil, user: nil, guest_token: token) }
  let(:user)  { build(:user, spree_api_key: 'fake') }
  let(:token) { 'some_token' }
  let(:cookie_token) { token }

  before do
    request.cookie_jar.signed[:guest_token] = cookie_token
    allow(controller).to receive(:current_order) { order }
  end

  context '#edit' do
    context 'when registration step enabled' do
      context 'when authenticated as registered user' do
        before { allow(controller).to receive(:spree_current_user) { user } }

        it 'proceeds to the first checkout step' do
          get :edit, params: { state: 'address' }
          expect(response).to render_template :edit
        end
      end

      # Guest checkout is closed. Wholesale accounts are approval-gated, so
      # there is no such thing as a guest wholesale customer -- and pricing is
      # not shown to anyone signed out, which is most of what checkout is for.
      #
      # Nsb::RequiresWholesaleAccount turns the request away before Solidus's
      # own guest handling is reached, so allow_guest_checkout and the
      # registration step no longer decide anything here.
      context 'when not signed in' do
        it 'is sent to the welcome page rather than the registration step' do
          get :edit, params: { state: 'address' }
          expect(response).to redirect_to '/welcome'
        end

        it 'is still turned away when the order has a guest email' do
          order.email = 'guest@solidus.io'

          get :edit, params: { state: 'address' }
          expect(response).to redirect_to '/welcome'
        end
      end
    end

    context 'when registration step disabled' do
      before do
        stub_spree_preferences(Spree::Auth::Config, registration_step: false)
      end

      context 'when authenticated as registered' do
        before { allow(controller).to receive(:spree_current_user) { user } }

        it 'proceeds to the first checkout step' do
          get :edit, params: { state: 'address' }
          expect(response).to render_template :edit
        end
      end

      context 'when not signed in' do
        it 'is turned away even with the registration step disabled' do
          get :edit, params: { state: 'address' }
          expect(response).to redirect_to '/welcome'
        end
      end
    end
  end

  context '#update' do
    context 'when in the confirm state' do
      before do
        order.update(email: 'spree@example.com', state: 'confirm')

        # So that the order can transition to complete successfully
        allow(order).to receive(:payment_required?) { false }
      end

      # Completing an order on a guest token alone is part of the same closed
      # path: the order could only have been built by someone signed in, and
      # they are asked to sign in again rather than finish anonymously. Reading
      # a finished order by token still works -- OrdersController is
      # deliberately not gated, because that link is in the customer's own
      # confirmation email.
      context 'with a token but not signed in' do
        before { allow(order).to receive(:guest_token) { 'ABC' } }

        it 'does not complete the order' do
          request.cookie_jar.signed[:guest_token] = 'ABC'
          post :update, params: { state: 'confirm' }
          expect(response).to redirect_to '/welcome'
        end
      end

      context 'with a registered user' do
        before do
          allow(controller).to receive(:spree_current_user) { user }
          allow(order).to receive(:user) { user }
          allow(order).to receive(:guest_token) { nil }
        end

        it 'redirects to the standard order view' do
          post :update, params: { state: 'confirm' }
          expect(response).to redirect_to order_path(order)
        end
      end
    end
  end
end
