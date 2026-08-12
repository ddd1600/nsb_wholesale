# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# EMAIL_SETUP.md, build requirement 1: "Email failure must never break checkout."
#
# Solidus finalizes an order inside a state-machine transaction and publishes
# :order_finalized from within it. If the confirmation email were delivered
# synchronously there, a transient Gmail failure would raise inside that
# transaction and roll back an order Square has already charged -- real money,
# and invisible in a passing test suite.
#
# These examples pin the property that makes that impossible: delivery is
# enqueued, never performed inline during checkout.
RSpec.describe "Order confirmation email delivery" do
  let(:order) { create(:order_ready_to_complete) }

  it "enqueues the confirmation rather than delivering it during checkout" do
    expect { order.complete! }
      .to have_enqueued_job(ActionMailer::MailDeliveryJob)

    # Nothing was delivered inline, so no SMTP conversation happened inside the
    # transaction that completed the order.
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(order.reload).to be_completed
  end

  it "keeps the completed order when sending the confirmation later fails" do
    order.complete!
    expect(order.reload).to be_completed

    # Simulate Gmail refusing the message when the queued job finally runs.
    allow(ActionMailer::Base).to receive(:deliver_mail)
      .and_raise(Net::SMTPAuthenticationError.new("535 Username and Password not accepted"))

    expect { perform_enqueued_jobs }.to raise_error(Net::SMTPAuthenticationError)

    # The order is the source of truth; the email is only a notification.
    expect(order.reload).to be_completed
    expect(order.completed_at).to be_present
  end

  it "does not roll back checkout when delivery fails inline" do
    # Worst case: someone switches ActiveJob to the :inline adapter, so
    # deliver_later runs during the transaction. The order must still survive.
    allow(ActionMailer::Base).to receive(:deliver_mail)
      .and_raise(Net::SMTPServerBusy.new("451 Try again later"))

    perform_enqueued_jobs do
      order.complete!
    rescue Net::SMTPServerBusy
      # Surfacing the error is fine; losing the order is not.
    end

    expect(order.reload).to be_completed
  end
end
