# frozen_string_literal: true

module Nsb
  # Attaches the printable PDF invoice (Nsb::InvoicePdf) to Solidus's order
  # confirmation email. The email's own body is the invoice too: see
  # app/views/spree/order_mailer/confirm_email.{html,text}.erb.
  #
  # Still Solidus's Spree::OrderMailer#confirm_email, sent by Solidus on
  # :order_finalized and delivered from the job queue -- this only adds the
  # attachment. Staff get their copy through the store's stock "BCC Email"
  # field, which that method already BCCs.
  #
  # Attachments must be added before #mail is called, hence before super.
  #
  # Prepended onto Spree::OrderMailer in config/initializers/solidus_decorators.rb.
  module OrderConfirmationInvoice
    def confirm_email(order, resend = false)
      pdf = Nsb::InvoicePdf.new(Nsb::Invoice.new(order))
      attachments[pdf.filename] = { mime_type: "application/pdf", content: pdf.render }
      super
    end
  end
end
