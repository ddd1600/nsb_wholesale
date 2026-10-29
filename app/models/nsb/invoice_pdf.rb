# frozen_string_literal: true

require "prawn"
require "prawn/table"

module Nsb
  # The printable PDF invoice attached to each order confirmation email
  # (Nsb::OrderConfirmationInvoice). Content comes from Nsb::Invoice, the same
  # source as the email body.
  #
  # Prawn's built-in Helvetica only covers Windows-1252 characters, which is
  # every product name in the catalog today; anything outside it is replaced
  # rather than failing the email.
  class InvoicePdf
    # safe() below already handles what the warning is about.
    Prawn::Fonts::AFM.hide_m17n_warning = true

    MARGIN = 40
    GREY = "666666"
    RULE = "CCCCCC"

    def initialize(invoice)
      @invoice = invoice
    end

    def filename = "invoice-#{@invoice.number}.pdf"

    def render
      Prawn::Document.new(page_size: "LETTER", margin: MARGIN, info: { Title: "Invoice #{@invoice.number}" }) do |pdf|
        pdf.font "Helvetica", size: 10
        header(pdf)
        parties(pdf)
        items(pdf)
        footer(pdf)
      end.render
    end

    private

    def header(pdf)
      top = pdf.cursor
      pdf.image @invoice.logo_path.to_s, height: 54 if File.exist?(@invoice.logo_path)

      pdf.bounding_box([ pdf.bounds.width - 220, top ], width: 220) do
        pdf.text "INVOICE", size: 20, style: :bold, align: :right
        pdf.text "Order #{safe(@invoice.number)}", align: :right
        pdf.text @invoice.date.to_fs(:long), align: :right
        pdf.text safe(@invoice.payment_summary), align: :right, color: GREY
      end

      pdf.move_down 12
      from = [ @invoice.business_name, *@invoice.mailing_address_lines, @invoice.phone, @invoice.email ].compact_blank
      pdf.text from.map { |line| safe(line) }.join("\n"), color: GREY
      pdf.move_down 16
    end

    def parties(pdf)
      top = pdf.cursor
      half = pdf.bounds.width / 2
      [ [ "Bill to", @invoice.bill_address, 0 ], [ "Ship to", @invoice.ship_address, half ] ].each do |label, address, x|
        pdf.bounding_box([ x, top ], width: half - 10) do
          pdf.text label.upcase, size: 8, style: :bold, color: GREY
          lines = @invoice.address_lines(address)
          lines = [ @invoice.customer_name, @invoice.order.email ].compact_blank if lines.empty?
          pdf.text lines.map { |line| safe(line) }.join("\n")
        end
      end
      pdf.move_down 20
    end

    def items(pdf)
      data = [ %w[Product Variety SKU Qty Price Amount] ] +
        @invoice.rows.map do |row|
          [ safe(row.product), safe(row.variety), safe(row.sku), row.quantity.to_s, row.unit_price, row.amount ]
        end

      pdf.table(data, header: true, width: pdf.bounds.width,
        column_widths: { 3 => 40, 4 => 70, 5 => 75 },
        cell_style: { size: 9, padding: [ 5, 6 ], borders: [ :bottom ], border_color: RULE }) do |table|
        table.row(0).font_style = :bold
        table.row(0).background_color = "F2F2F2"
        table.columns(3..5).align = :right
      end

      pdf.move_down 8
      totals = @invoice.totals.map { |total| [ safe(total.label), total.amount ] }
      pdf.table(totals, position: :right, column_widths: [ 200, 75 ],
        cell_style: { size: 10, padding: [ 3, 6 ], borders: [] }) do |table|
        table.columns(0..1).align = :right
        table.row(-1).font_style = :bold
        table.row(-1).size = 12
        table.row(-1).borders = [ :top ]
        table.row(-1).border_color = RULE
      end
    end

    def footer(pdf)
      pdf.move_down 24
      pdf.stroke_color RULE
      pdf.stroke_horizontal_rule
      pdf.move_down 10
      contact = [ @invoice.phone, @invoice.email ].compact_blank.join("  ·  ")
      pdf.text safe(@invoice.notice), style: :bold if @invoice.notice.present?
      pdf.text safe(contact) if contact.present?
      pdf.text "Thank you for your order!", color: GREY
    end

    # Replace anything Helvetica (Windows-1252) cannot draw.
    def safe(text)
      text.to_s.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?").encode("UTF-8")
    end
  end
end
