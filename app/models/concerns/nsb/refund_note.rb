# frozen_string_literal: true

module Nsb
  # Free-text note on a refund, so the operator can say what actually happened
  # when the reason list doesn't cover it.
  #
  # Stored in the existing admin_metadata jsonb column rather than a new one: it
  # needs no migration, and admin_metadata is exactly what Solidus provides that
  # column for. "admin" is right -- this is internal, never shown to customers.
  #
  # Prepended onto Spree::Refund in config/initializers/solidus_decorators.rb.
  module RefundNote
    extend ActiveSupport::Concern

    NOTE_KEY = "note"

    def note
      admin_metadata&.dig(NOTE_KEY)
    end

    def note=(value)
      self.admin_metadata = (admin_metadata || {}).merge(NOTE_KEY => value.to_s.strip.presence)
        .compact
    end

    # Shown in the admin payments list next to the reason.
    # NB the association is `reason`, not `refund_reason` -- only the foreign key
    # is called refund_reason_id.
    def reason_with_note
      [reason&.name, note.presence].compact.join(" - ")
    end
  end
end
