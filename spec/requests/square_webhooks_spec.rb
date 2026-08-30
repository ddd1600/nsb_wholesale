# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# A refund issued in the Square dashboard used to be invisible to Solidus: the
# operator's money moved and the order went on reading as fully paid. This
# records it.
#
# The assertions that matter most are the refusals. This endpoint is
# unauthenticated apart from its signature, and it writes to orders.
RSpec.describe "Square refund webhooks", type: :request do
  let(:signature_key) { "test-signature-key" }
  let(:notification_url) { "https://wholesale.test/square/webhooks" }

  let(:order) { create(:order_ready_to_ship, line_items_price: 50, shipment_cost: 0) }
  let(:payment) { order.payments.first }
  let(:square_payment_id) { "sq-payment-abc" }
  let(:square_refund_id) { "sq-refund-xyz" }

  around do |example|
    ClimateControl.modify(
      SQUARE_WEBHOOK_SIGNATURE_KEY: signature_key,
      SQUARE_WEBHOOK_URL: notification_url
    ) { example.run }
  end

  before do
    payment.payment_method.update!(type: "Spree::PaymentMethod::SquareCreditCard")
    payment.update!(response_code: square_payment_id)
  end

  def event(refund_id: square_refund_id, payment_id: square_payment_id,
    amount_cents: 1000, status: "COMPLETED", type: "refund.created")
    {
      type: type,
      data: {
        type: "refund",
        object: {
          refund: {
            id: refund_id,
            payment_id: payment_id,
            status: status,
            amount_money: { amount: amount_cents, currency: "USD" }
          }
        }
      }
    }.to_json
  end

  def sign(body, key: signature_key, url: notification_url)
    Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", key, "#{url}#{body}"))
  end

  def post_event(body, signature: nil)
    post "/square/webhooks",
      params: body,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_X_SQUARE_HMACSHA256_SIGNATURE" => signature || sign(body)
      }
  end

  describe "a properly signed refund" do
    it "records it against the order" do
      body = event

      expect { post_event(body) }.to change(Spree::Refund, :count).by(1)

      expect(response).to have_http_status(:ok)
      refund = Spree::Refund.last
      expect(refund.payment).to eq(payment)
      expect(refund.amount).to eq(10.0)
      expect(refund.transaction_id).to eq(square_refund_id)
    end

    # The whole point: this writes down what Square already did. Calling the
    # gateway would refund the customer a second time.
    it "never calls Square" do
      expect_any_instance_of(Nsb::Square::Gateway).not_to receive(:credit)

      post_event(event)
    end

    it "updates the order so it no longer reads as fully paid" do
      expect { post_event(event) }.to change { order.reload.payment_state }
    end
  end

  describe "refusals" do
    it "rejects an invalid signature and writes nothing" do
      expect { post_event(event, signature: "not-the-signature") }
        .not_to change(Spree::Refund, :count)

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a body that was tampered with after signing" do
      body = event
      good_signature = sign(body)
      tampered = event(amount_cents: 5000)

      expect { post_event(tampered, signature: good_signature) }
        .not_to change(Spree::Refund, :count)

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a signature computed for a different notification URL" do
      body = event

      expect { post_event(body, signature: sign(body, url: "https://elsewhere.test/square/webhooks")) }
        .not_to change(Spree::Refund, :count)

      expect(response).to have_http_status(:unauthorized)
    end

    # Fail closed. An unset key must never mean "accept anything".
    it "rejects everything when no signature key is configured" do
      body = event
      signature = sign(body)
      ENV.delete("SQUARE_WEBHOOK_SIGNATURE_KEY")

      expect { post_event(body, signature: signature) }.not_to change(Spree::Refund, :count)

      expect(response).to have_http_status(:unauthorized)
    ensure
      ENV["SQUARE_WEBHOOK_SIGNATURE_KEY"] = signature_key
    end
  end

  describe "idempotency" do
    # Square retries until it gets a 2xx, and refund.updated follows
    # refund.created for the same refund.
    it "does not record the same refund twice" do
      post_event(event)

      expect { post_event(event(type: "refund.updated")) }.not_to change(Spree::Refund, :count)
      expect(response).to have_http_status(:ok)
    end

    # The race this is really guarding: the operator refunds from Solidus admin,
    # which writes a Spree::Refund with Square's refund id, and Square then
    # delivers the webhook for that same refund.
    it "ignores a refund Solidus already recorded itself" do
      Spree::Refund.create!(
        payment: payment,
        amount: 10.0,
        transaction_id: square_refund_id,
        reason: create(:refund_reason)
      )

      expect { post_event(event) }.not_to change(Spree::Refund, :count)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "events it should not act on" do
    it "ignores a PENDING refund, which can still fail" do
      expect { post_event(event(status: "PENDING")) }.not_to change(Spree::Refund, :count)

      expect(response).to have_http_status(:ok)
    end

    # Square also handles the retail business, whose payments have no order here.
    it "acknowledges a refund for a payment that is not ours" do
      expect { post_event(event(payment_id: "sq-payment-from-the-retail-shop")) }
        .not_to change(Spree::Refund, :count)

      expect(response).to have_http_status(:ok)
    end

    it "acknowledges event types it does not handle" do
      expect { post_event(event(type: "payment.created")) }.not_to change(Spree::Refund, :count)

      expect(response).to have_http_status(:ok)
    end
  end

  # Solidus refuses a refund larger than what is left to refund. That guard
  # firing means Square and Solidus disagree about the order, which a person
  # needs to look at -- so it must not be recorded and must not be silent.
  describe "when Square reports more than the order can refund" do
    it "records nothing and acknowledges, rather than retrying forever" do
      expect { post_event(event(amount_cents: 999_999)) }.not_to change(Spree::Refund, :count)

      expect(response).to have_http_status(:ok)
    end
  end
end
