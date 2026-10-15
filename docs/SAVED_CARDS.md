# Saved cards

Customers can tick **"Save this card for future orders"** at checkout. Square
keeps the card ("card on file"); we keep only Square's ids plus brand, last four
and expiry.

**Status (2026-10-15): built and tested against stubbed Square only. Not yet
tried against the Square sandbox or a real card.** Do the sandbox check first,
then the live check.

## How it works

1. Checkout charges the card exactly as before. The box starts unticked.
2. After Square confirms the charge and the order completes, a background job
   (`Nsb::SaveCardOnFileJob`) asks Square to save the card, using the completed
   payment as the source. It also creates a Square customer for the portal user
   the first time.
3. Next checkout, the saved card appears above "Square" as e.g. "Visa ending 4242".
4. Customers remove cards under **My Account → Saved cards**. Square is told first;
   if Square can't confirm, the card stays and the customer sees an error.
5. Admin: **Orders → (order) → Payments → New Payment → Square** lists the
   customer's saved cards. Choosing one and pressing Update charges it through
   Square. Impersonating the customer and checking out also works.

If saving fails, the order is unaffected and the customer types the card next
time. Failures are logged as `[square] could not save card ...`.

## Things I have not confirmed

- **Saving a card from a completed payment id.** Square's docs say CreateCard
  accepts a payment id as `source_id`. Not yet exercised.
- **Extra verification (3-D Secure) when saving.** Square may ask for a buyer
  verification token when storing a card. If the sandbox rejects saving without
  one, that is the fix needed.
- **Consent wording** under the checkbox is my draft. It covers phone/admin
  charges because you asked for those. Worth a read.

## Sandbox check (do first)

With sandbox credentials set locally, use Square's sandbox test card
`4111 1111 1111 1111`, any future expiry, any CVV, ZIP `94103`:

1. Check out with "Save this card" ticked.
2. In the Square **sandbox** dashboard → Customers, the customer appears with
   the card on file.
3. In the portal, My Account → Saved cards lists "Visa ending 1111".
4. Place a second order choosing the saved card. It is charged.
5. Remove the card from My Account. It disappears from the Square customer too.

## Live check (small real amount)

Once on production credentials:

1. **Save:** check out with a real card, box ticked. Charge appears in Square for
   the right amount; card appears on the customer in Square → Customers.
2. **Paid only after confirmation:** the order shows Paid in the admin only once
   the charge is in Square.
3. **Reuse:** a second order with the saved card is charged in Square for the
   right amount, and Paid in the admin.
4. **Not ticked:** an order with the box unticked leaves no card on the customer
   in Square.
5. **Declined saved card:** if you can, use a saved card that will decline (e.g.
   frozen in your banking app). The order stays unpaid and the customer sees a
   clear message.
6. **Admin charge:** from Orders → Payments → New Payment, charge the saved card
   $1. It appears in Square; refund it from the admin and confirm the refund in
   Square.
7. **Remove:** remove the card in My Account; it is gone from the customer in
   Square.
