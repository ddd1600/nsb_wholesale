# frozen_string_literal: true

require 'solidus_starter_frontend_spec_helper'

# This controller exists to let someone check out as a guest: it takes an email
# and attaches it to an order that has no user.
#
# That path is closed. Wholesale accounts are approval-gated -- existing
# customers claim the account already created for them, everyone else applies
# and waits -- so there is no such thing as a guest wholesale customer. Pricing
# is not shown to anyone signed out either, which is most of what checkout is
# for.
#
# The controller and its route are left in place rather than removed: checkout
# is the highest-stakes area in this application, and deleting paths through it
# is a change to make deliberately and on its own, not as a side effect of
# adding a welcome page. Nsb::RequiresWholesaleAccount closes the door; these
# examples are what says the door is shut.
RSpec.describe CheckoutGuestSessionsController, type: :controller do
  let(:order) { create(:order_with_line_items, email: nil, user: nil, guest_token: token) }
  let(:token) { 'some_token' }

  before do
    request.cookie_jar.signed[:guest_token] = token
    allow(controller).to receive(:current_order) { order }
  end

  context '#create' do
    subject { post :create, params: { order: { email: 'foo@example.com' } } }

    it 'refuses an anonymous visitor and sends them to the welcome page' do
      subject

      expect(response).to redirect_to '/welcome'
    end

    it 'does not attach a guest email to the order' do
      expect { subject }.not_to change { order.reload.email }
    end

    # The gate runs before the controller's own logic, so a valid guest token
    # buys nothing here.
    it 'refuses even with a matching order token' do
      request.cookie_jar.signed[:guest_token] = token

      subject

      expect(response).to redirect_to '/welcome'
    end
  end
end
