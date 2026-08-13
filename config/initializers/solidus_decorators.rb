# frozen_string_literal: true

# Solidus's models live inside the gem, so app-side behaviour is added by
# prepending modules onto them. to_prepare re-applies these on every reload in
# development; a plain initializer would attach to a stale class after the first
# code reload.
#
# Keep this list short and each module small -- see CLAUDE.md.
Rails.application.config.to_prepare do
  # Account claiming for customers migrated from B2BWave.
  Spree.user_class.prepend(Nsb::UserClaimable)

  # Free-text note on refunds, paired with the "Other" refund reason.
  Spree::Refund.prepend(Nsb::RefundNote)
end
