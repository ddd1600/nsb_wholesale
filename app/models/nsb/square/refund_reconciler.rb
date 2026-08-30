# frozen_string_literal: true

module Nsb
  module Square
    # Records a refund that happened in Square against the Solidus order.
    #
    # Refunds issued from the Solidus admin already reconcile: Solidus calls the
    # gateway and writes a Spree::Refund itself. A refund issued in the Square
    # dashboard did not, and the order went on reading as fully paid -- the
    # operator's own money moving without the books noticing. This closes that.
    #
    # THE RULE: this never calls Square. It only writes down what Square has
    # already done. Spree::Refund#perform! is what talks to the gateway, and it
    # is never called here -- the record is created with transaction_id already
    # set, which is also what makes perform! a no-op if anything calls it later.
    # Getting this wrong would refund the customer twice.
    class RefundReconciler
      # Square's own status for "the money has moved". PENDING refunds are
      # deliberately ignored: they can still fail, and reducing what the order
      # reads as paid on the strength of a maybe is the wrong way round. Square
      # sends refund.updated when a pending refund completes, and that is when
      # this records it.
      COMPLETED = "COMPLETED"

      REASON_NAME = "Refunded in Square"

      Result = Struct.new(:outcome, :refund, :message, keyword_init: true) do
        def recorded? = outcome == :recorded
        def to_s = [ outcome, message ].compact.join(": ")
      end

      def initialize(logger: Rails.logger)
        @logger = logger
      end

      # payload is the "refund" object from the webhook event.
      def call(payload)
        square_refund_id = payload["id"].presence
        square_payment_id = payload["payment_id"].presence
        status = payload["status"]

        return result(:invalid, "webhook carried no refund id") if square_refund_id.blank?

        unless status == COMPLETED
          return result(:ignored, "refund #{square_refund_id} is #{status.inspect}, not #{COMPLETED}")
        end

        payment = find_payment(square_payment_id)
        if payment.nil?
          # Not necessarily wrong: Square handles the retail business too, and
          # those payments have no order here. Logged rather than raised so a
          # retail refund does not look like a failure and get retried forever.
          return result(:unmatched, "no Solidus payment with response_code #{square_payment_id.inspect}")
        end

        record(payment, payload, square_refund_id)
      end

      private

      attr_reader :logger

      # Locked for the duration, because the operator refunding from Solidus
      # admin at the same moment as Square delivers the webhook is exactly the
      # race that would write the refund twice. The existence check has to
      # happen inside the lock to be worth anything.
      def record(payment, payload, square_refund_id)
        payment.with_lock do
          if Spree::Refund.exists?(transaction_id: square_refund_id)
            return result(:already_recorded, "refund #{square_refund_id} is already on the order")
          end

          refund = payment.refunds.build(
            amount: amount_from(payload, payment),
            # Set BEFORE save, which is what keeps this a bookkeeping entry
            # rather than a second refund: Spree::Refund#perform! returns early
            # when transaction_id is present, and nothing here calls it anyway.
            transaction_id: square_refund_id,
            reason: refund_reason
          )

          unless refund.save
            # The likeliest cause is Solidus's own guard that a refund cannot
            # exceed what is left to refund -- which means Square and Solidus
            # disagree about this order, and a person needs to look.
            message = refund.errors.full_messages.to_sentence
            say("REFUSED refund #{square_refund_id} on payment #{payment.id}: #{message}")
            return result(:rejected, message)
          end

          payment.order.recalculate
          say("recorded refund #{square_refund_id} (#{refund.display_amount}) on order #{payment.order.number}")
          result(:recorded, "recorded on order #{payment.order.number}", refund: refund)
        end
      end

      # Only payments this store took through Square. Matching on response_code
      # alone could collide with another gateway's identifier.
      def find_payment(square_payment_id)
        return nil if square_payment_id.blank?

        Spree::Payment
          .joins(:payment_method)
          .where(spree_payment_methods: { type: "Spree::PaymentMethod::SquareCreditCard" })
          .find_by(response_code: square_payment_id)
      end

      # Square reports minor units. Converted through the money gem rather than
      # dividing by 100, so a currency without two decimal places would not be
      # silently off by a factor of a hundred.
      def amount_from(payload, payment)
        cents = payload.dig("amount_money", "amount").to_i
        currency = payload.dig("amount_money", "currency").presence || payment.currency

        ::Money.new(cents, currency).to_d
      end

      def refund_reason
        @refund_reason ||= Spree::RefundReason.find_or_create_by!(name: REASON_NAME) do |reason|
          reason.active = true
          # Not mutable: this reason means something specific -- the money moved
          # outside Solidus -- and renaming it would make the order history lie.
          reason.mutable = false
        end
      end

      def result(outcome, message, refund: nil)
        Result.new(outcome: outcome, message: message, refund: refund)
      end

      def say(message)
        logger.info("[square-webhook] #{message}")
      end
    end
  end
end
