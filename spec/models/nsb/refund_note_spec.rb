# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

RSpec.describe Nsb::RefundNote do
  let(:refund) { build(:refund) }

  it "stores the note in admin_metadata, needing no new column" do
    refund.note = "Customer reported a leaking bottle"

    expect(refund.admin_metadata["note"]).to eq("Customer reported a leaking bottle")
    expect(refund.note).to eq("Customer reported a leaking bottle")
  end

  it "survives a round trip through the database" do
    refund.note = "Duplicate of order R123"
    refund.save!

    expect(refund.reload.note).to eq("Duplicate of order R123")
  end

  it "treats a blank note as no note" do
    refund.note = "   "

    expect(refund.note).to be_nil
  end

  it "does not clobber other admin_metadata keys" do
    refund.admin_metadata = { "existing" => "value" }
    refund.note = "A note"

    expect(refund.admin_metadata).to include("existing" => "value", "note" => "A note")
  end

  it "combines reason and note for display" do
    reason = create(:refund_reason, name: "Other")
    refund.reason = reason
    refund.note = "Shipping quoted wrong"

    expect(refund.reason_with_note).to eq("Other - Shipping quoted wrong")
  end

  it "falls back to the reason alone when there is no note" do
    refund.reason = create(:refund_reason, name: "Damaged in transit")

    expect(refund.reason_with_note).to eq("Damaged in transit")
  end

  describe Nsb::RefundReasonSeeder do
    it "adds the operator's reasons and is safe to re-run" do
      described_class.new.call
      expect { described_class.new.call }.not_to change { Spree::RefundReason.count }
      expect(Spree::RefundReason.pluck(:name)).to include("Other", "Damaged in transit", "Duplicate charge")
    end
  end
end
