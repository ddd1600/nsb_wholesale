# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# These examples exist to catch the specific failure CLAUDE.md warns about: a
# payment path that passes its tests while marking orders paid when Square never
# confirmed the money moved. Most of them assert on FAILURE, not success.
RSpec.describe Nsb::Square::Gateway do
  subject(:gateway) { described_class.new }

  let(:payments_api) { instance_double("Square::Payments::Client") }
  let(:refunds_api) { instance_double("Square::Refunds::Client") }
  let(:square_client) { instance_double("Square::Client", payments: payments_api, refunds: refunds_api) }
  let(:config) do
    instance_double(
      Nsb::Square::Configuration,
      client: square_client, location_id: "LOC1", currency: "USD", configured?: true
    )
  end

  let(:source) { double("Spree::CreditCard", gateway_payment_profile_id: "cnon:card-nonce-ok") }
  let(:gateway_options) { { order_id: "R123456789-P4444", currency: "USD", email: "buyer@example.com" } }

  before { allow(Nsb::Square::Configuration).to receive(:new).and_return(config) }

  def square_payment(status:, id: "sq-pay-1", card_details: nil)
    double("Square::Types::Payment", id: id, status: status, receipt_url: "https://sq/r/1",
                                     order_id: "sq-order-1", card_details: card_details)
  end

  def create_response(payment)
    double("CreatePaymentResponse", payment: payment)
  end

  describe "#purchase" do
    it "reports success only when Square says COMPLETED" do
      allow(payments_api).to receive(:create).and_return(create_response(square_payment(status: "COMPLETED")))

      response = gateway.purchase(2500, source, gateway_options)

      expect(response).to be_success
      # Solidus stores this as response_code and later refunds against it.
      expect(response.authorization).to eq("sq-pay-1")
    end

    # The heart of it: every non-confirming status must fail, not pass.
    %w[APPROVED PENDING FAILED CANCELED].each do |status|
      it "does NOT report success when Square returns #{status}" do
        allow(payments_api).to receive(:create).and_return(create_response(square_payment(status: status)))

        expect(gateway.purchase(2500, source, gateway_options)).not_to be_success
      end
    end

    it "reads AVS and CVV from card_details, where Square actually puts them" do
      details = double("CardPaymentDetails", avs_status: "AVS_ACCEPTED", cvv_status: "CVV_ACCEPTED")
      allow(payments_api).to receive(:create)
        .and_return(create_response(square_payment(status: "COMPLETED", card_details: details)))

      response = gateway.purchase(2500, source, gateway_options)

      expect(response.avs_result["code"]).to eq("AVS_ACCEPTED")
      expect(response.cvv_result["code"]).to eq("CVV_ACCEPTED")
    end

    # Regression: avs_status/cvv_status were read off the nested Card object,
    # which does not define them. That raised NoMethodError AFTER Square had
    # already charged the customer -- money taken, order not marked paid.
    it "still succeeds when the card details object lacks AVS/CVV entirely" do
      bare = Object.new
      allow(payments_api).to receive(:create)
        .and_return(create_response(square_payment(status: "COMPLETED", card_details: bare)))

      response = nil
      expect { response = gateway.purchase(2500, source, gateway_options) }.not_to raise_error
      expect(response).to be_success
      expect(response.authorization).to eq("sq-pay-1")
    end

    it "never lets a response-building error discard a confirmed charge" do
      exploding = double("CardPaymentDetails")
      allow(exploding).to receive(:try).and_raise(RuntimeError, "unexpected shape")
      allow(payments_api).to receive(:create)
        .and_return(create_response(square_payment(status: "COMPLETED", card_details: exploding)))

      response = gateway.purchase(2500, source, gateway_options)

      expect(response).to be_success
      expect(response.authorization).to eq("sq-pay-1")
    end

    it "does not report success when Square returns no payment at all" do
      allow(payments_api).to receive(:create).and_return(create_response(nil))

      expect(gateway.purchase(2500, source, gateway_options)).not_to be_success
    end

    it "sends the amount and currency Solidus asked for" do
      allow(payments_api).to receive(:create).and_return(create_response(square_payment(status: "COMPLETED")))

      gateway.purchase(2500, source, gateway_options)

      expect(payments_api).to have_received(:create)
        .with(hash_including(amount_money: { amount: 2500, currency: "USD" }))
    end

    it "refuses to call Square when the browser supplied no token" do
      tokenless = double("Spree::CreditCard", gateway_payment_profile_id: nil)
      allow(payments_api).to receive(:create)

      response = gateway.purchase(2500, tokenless, gateway_options)

      expect(response).not_to be_success
      expect(payments_api).not_to have_received(:create)
    end
  end

  describe "idempotency" do
    it "derives a stable key from the Solidus payment, so a double-click cannot double-charge" do
      keys = []
      allow(payments_api).to receive(:create) do |**kwargs|
        keys << kwargs[:idempotency_key]
        create_response(square_payment(status: "COMPLETED"))
      end

      # Two submissions of the SAME Spree::Payment, i.e. an impatient customer
      # clicking Place Order twice.
      2.times { gateway.purchase(2500, source, gateway_options) }

      expect(keys.size).to eq(2)
      expect(keys.uniq.size).to eq(1)
      expect(keys.first).to include("R123456789-P4444")
    end

    it "uses a different key for a different payment attempt" do
      keys = []
      allow(payments_api).to receive(:create) do |**kwargs|
        keys << kwargs[:idempotency_key]
        create_response(square_payment(status: "COMPLETED"))
      end

      gateway.purchase(2500, source, gateway_options)
      # A retry after a decline is a new Spree::Payment, so a new key -- it must
      # NOT be deduplicated against the earlier attempt.
      gateway.purchase(2500, source, gateway_options.merge(order_id: "R123456789-P5555"))

      expect(keys.uniq.size).to eq(2)
    end

    it "uses a different key for a refund than for the charge" do
      allow(payments_api).to receive(:create).and_return(create_response(square_payment(status: "COMPLETED")))
      allow(refunds_api).to receive(:refund_payment)
        .and_return(double("resp", refund: double("refund", id: "sq-ref-1", status: "COMPLETED")))

      gateway.purchase(2500, source, gateway_options)
      gateway.credit(1000, "sq-pay-1", gateway_options)

      expect(refunds_api).to have_received(:refund_payment) { |**kwargs|
        expect(kwargs[:idempotency_key]).to start_with("refund-")
      }
    end
  end

  describe "network failures" do
    it "raises ConnectionError on a timeout rather than guessing the outcome" do
      allow(payments_api).to receive(:create).and_raise(Square::Errors::TimeoutError)

      # Solidus turns this into a GatewayError WITHOUT completing the payment.
      expect { gateway.purchase(2500, source, gateway_options) }
        .to raise_error(ActiveMerchant::ConnectionError, /may or may not have completed/)
    end

    it "raises ConnectionError on a Square 5xx" do
      allow(payments_api).to receive(:create)
        .and_raise(Square::Errors::ServerError.new("boom", code: 500))

      expect { gateway.purchase(2500, source, gateway_options) }
        .to raise_error(ActiveMerchant::ConnectionError)
    end

    it "fails cleanly, without a 500, when Square credentials are missing" do
      allow(config).to receive(:client)
        .and_raise(Nsb::Square::Configuration::MissingCredentials, "missing SQUARE_ACCESS_TOKEN")

      # A misconfigured server must not crash checkout, and must not leave the
      # order looking paid.
      expect { gateway.purchase(2500, source, gateway_options) }
        .to raise_error(ActiveMerchant::ConnectionError, /Card payment is unavailable/)
    end

    it "never returns a successful response from an error path" do
      allow(payments_api).to receive(:create).and_raise(Square::Errors::TimeoutError)

      begin
        response = gateway.purchase(2500, source, gateway_options)
        expect(response).not_to be_success
      rescue ActiveMerchant::ConnectionError
        # Raising is the correct behaviour; the point is that it never succeeds.
      end
    end
  end

  describe "declined cards" do
    let(:decline_body) do
      { errors: [{ category: "PAYMENT_METHOD_ERROR", code: "CARD_DECLINED",
                   detail: "Card declined by the issuing bank." }] }.to_json
    end

    it "returns a failed response with a message a customer can act on" do
      allow(payments_api).to receive(:create)
        .and_raise(Square::Errors::ClientError.new(decline_body, code: 402))

      response = gateway.purchase(2500, source, gateway_options)

      expect(response).not_to be_success
      expect(response.message).to eq(described_class::CUSTOMER_MESSAGES["CARD_DECLINED"] ||
                                     described_class::GENERIC_DECLINE_MESSAGE)
    end

    # Square's raw wording -- "Authorization error: 'GENERIC_DECLINE'" -- reads
    # like a fault in our site rather than a card problem.
    it "never shows the customer a raw Square error code" do
      %w[GENERIC_DECLINE CVV_FAILURE INSUFFICIENT_FUNDS SOMETHING_WE_HAVE_NOT_MAPPED].each do |code|
        body = { errors: [{ category: "PAYMENT_METHOD_ERROR", code: code,
                            detail: "Authorization error: '#{code}'" }] }.to_json
        allow(payments_api).to receive(:create)
          .and_raise(Square::Errors::ClientError.new(body, code: 402))

        message = gateway.purchase(2500, source, gateway_options).message

        expect(message).not_to include(code)
        expect(message).not_to match(/Authorization error/i)
        expect(message).to match(/card|payment|bank|funds|expir|address|security code/i)
      end
    end

    it "translates a generic decline into plain English" do
      body = { errors: [{ code: "GENERIC_DECLINE", detail: "Authorization error: 'GENERIC_DECLINE'" }] }.to_json
      allow(payments_api).to receive(:create)
        .and_raise(Square::Errors::ClientError.new(body, code: 402))

      expect(gateway.purchase(2500, source, gateway_options).message)
        .to eq("Your card was declined. Please try another card, or contact your bank.")
    end

    it "explains a CVV mismatch specifically" do
      body = { errors: [{ code: "CVV_FAILURE", detail: "Authorization error: 'CVV_FAILURE'" }] }.to_json
      allow(payments_api).to receive(:create)
        .and_raise(Square::Errors::ClientError.new(body, code: 402))

      expect(gateway.purchase(2500, source, gateway_options).message).to include("security code")
    end

    it "does not raise, so checkout can show the customer the error" do
      allow(payments_api).to receive(:create)
        .and_raise(Square::Errors::ClientError.new(decline_body, code: 402))

      expect { gateway.purchase(2500, source, gateway_options) }.not_to raise_error
    end
  end

  describe "#authorize and #capture" do
    it "treats APPROVED as a successful authorization" do
      allow(payments_api).to receive(:create).and_return(create_response(square_payment(status: "APPROVED")))

      expect(gateway.authorize(2500, source, gateway_options)).to be_success
    end

    it "does not treat an un-captured authorization as a completed purchase" do
      allow(payments_api).to receive(:create).and_return(create_response(square_payment(status: "APPROVED")))
      allow(payments_api).to receive(:create).and_return(create_response(square_payment(status: "APPROVED")))

      expect(gateway.purchase(2500, source, gateway_options)).not_to be_success
    end

    it "reports success on capture only when Square confirms COMPLETED" do
      allow(payments_api).to receive(:complete).and_return(create_response(square_payment(status: "COMPLETED")))

      expect(gateway.capture(2500, "sq-pay-1", gateway_options)).to be_success
    end

    it "fails a capture Square did not confirm" do
      allow(payments_api).to receive(:complete).and_return(create_response(square_payment(status: "APPROVED")))

      expect(gateway.capture(2500, "sq-pay-1", gateway_options)).not_to be_success
    end
  end

  describe "#void" do
    it "succeeds only on a CANCELED status" do
      allow(payments_api).to receive(:cancel).and_return(create_response(square_payment(status: "CANCELED")))

      expect(gateway.void("sq-pay-1", gateway_options)).to be_success
    end

    it "fails when Square reports the payment is still live" do
      allow(payments_api).to receive(:cancel).and_return(create_response(square_payment(status: "COMPLETED")))

      expect(gateway.void("sq-pay-1", gateway_options)).not_to be_success
    end
  end

  describe "#credit (refunds)" do
    def refund_response(status)
      double("resp", refund: double("refund", id: "sq-ref-1", status: status))
    end

    it "refunds a partial amount" do
      allow(refunds_api).to receive(:refund_payment).and_return(refund_response("COMPLETED"))

      response = gateway.credit(1000, "sq-pay-1", gateway_options)

      expect(response).to be_success
      expect(refunds_api).to have_received(:refund_payment)
        .with(hash_including(amount_money: { amount: 1000, currency: "USD" }, payment_id: "sq-pay-1"))
    end

    it "accepts PENDING, which is a real settling state at Square" do
      allow(refunds_api).to receive(:refund_payment).and_return(refund_response("PENDING"))

      expect(gateway.credit(2500, "sq-pay-1", gateway_options)).to be_success
    end

    it "fails a refund Square rejected" do
      allow(refunds_api).to receive(:refund_payment).and_return(refund_response("FAILED"))

      expect(gateway.credit(2500, "sq-pay-1", gateway_options)).not_to be_success
    end
  end
end
