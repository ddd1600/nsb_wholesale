# frozen_string_literal: true

# The front door for a visitor who is not signed in.
#
# The two ways in are genuinely different and the wrong one wastes everybody's
# time: 360 businesses already have accounts waiting to be claimed, and telling
# one of them to fill in an application would create a duplicate for the operator
# to reconcile. So the page asks the question directly rather than presenting a
# single "get started" button.
class WelcomeController < StoreController
  def index
    # A signed-in customer has no use for this page; send them to the catalog.
    redirect_to root_path and return if spree_current_user.present?
  end
end
