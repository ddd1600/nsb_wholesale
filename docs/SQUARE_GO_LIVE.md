# Square go-live checklist

Everything below has been verified against Square **Sandbox**. None of it has
been verified with real money. Do not treat the payment integration as finished
until the live checks in this document pass.

Written 2026-08-13.

---

## What is already verified (Sandbox)

| Check | Status |
|---|---|
| Successful charge appears in Square for the right amount | ✅ |
| Order marked paid **only** after Square confirms | ✅ |
| Declined card leaves the order unpaid, customer sees a clear reason | ✅ |
| Refund from Solidus admin reconciles in Square | ✅ (partial refund) |

Not yet exercised anywhere:

- A **full** refund (only a partial was tested).
- A network timeout mid-charge. The code path is unit-tested and raises rather
  than guessing, but it has never happened against a real Square endpoint.

---

## Before the first live transaction

1. **Create production credentials** in the Square Developer Dashboard, with the
   toggle set to **Production**, not Sandbox.

2. **Set these on Render** (Environment → Environment Variables):

   | Variable | Notes |
   |---|---|
   | `SQUARE_ACCESS_TOKEN` | **Production** token. Secret. |
   | `SQUARE_LOCATION_ID` | Production location, not the sandbox one. |
   | `SQUARE_APPLICATION_ID` | Production app id. Public — appears in page source. |
   | `SQUARE_ENVIRONMENT` | `production` |

   The app defaults to Sandbox everywhere except `RAILS_ENV=production`, so a
   laptop cannot reach the live account by accident. The only way to charge a
   real card locally is to deliberately export a production token.

3. **Confirm the payment method is active**: `bin/rails nsb:square:enable`, then
   check `/admin/payment_methods` shows "Credit Card" as active.

4. **Check the sandbox test data is gone** from the production database — there
   should be no `sandbox-tester@example.com` user and no test orders.

---

## Square refund webhook

Refunds issued in the Square dashboard reconcile into Solidus through a webhook.
Without this configured, they do not -- and the failure is silent, which is what
makes it worth setting up before the first live refund rather than after.

**In Square's Developer Console → your application → Webhooks → Subscriptions:**

1. Add a subscription with the **Production** toggle set.
2. Notification URL: `https://wholesale.newsouthbotanicals.com/square/webhooks`
3. Subscribe to **`refund.created`** and **`refund.updated`**.
4. Copy the **signature key** it generates.

**On Render:**

| Variable | Value |
|---|---|
| `SQUARE_WEBHOOK_SIGNATURE_KEY` | The signature key from the subscription. Secret. |
| `SQUARE_WEBHOOK_URL` | Only if the notification URL differs from `https://<APP_HOST>/square/webhooks`. |

The URL must match **byte for byte** what Square is configured with: Square signs
the URL it was given, not the one the request arrived on, so a trailing slash or
a `www.` is the difference between every event verifying and none of them.

Square's "Send test event" button in the console is the quickest way to confirm
the signature key is right -- a valid event answers 200, a bad key answers 401.

**Without `SQUARE_WEBHOOK_SIGNATURE_KEY` set, the endpoint rejects everything.**
That is deliberate: an unset key must never mean "accept anything", since this
endpoint writes refunds onto orders.

The site password gate lets `/square/webhooks` through, because Square has no
password to give and gating it would make refunds silently fail to reconcile
while the site is still private.

## The live test — use a real card, small amount

Place a genuine order through the storefront for the smallest sensible amount.
A £/$1–5 marketing item works; the Trifold Brochure imports at 0.00 so pick
something priced.

### 1. The charge

- [ ] Order completes and shows an order confirmation page
- [ ] Square dashboard shows a payment for **exactly** the order total
- [ ] The Solidus payment's Transaction ID matches the Square payment id
- [ ] The order confirmation email arrives (from `connect@newsouthbotanicals.com`)

### 2. Paid only after confirmation

- [ ] In Solidus admin the order shows `payment_state: paid`
- [ ] The payment state is `completed`, not `processing` or `pending`

If a payment ever sits in `processing`, something raised between Square
confirming and Solidus recording it. Check the Square dashboard before assuming
the customer was not charged.

### 3. A declined card

Ask your bank for a card you can decline, or use a card with insufficient funds.

- [ ] The customer stays on the payment page
- [ ] The message is plain English, not a code like `GENERIC_DECLINE`
- [ ] The order is **not** marked paid
- [ ] No charge appears in the Square dashboard

### 4. Refunds — both directions

**From Solidus (the supported route):**

- [ ] Refund part of the order from the order's Payments tab
- [ ] The refund appears in Square within a minute
- [ ] Repeat for the remaining balance — a **full** refund, which sandbox did not cover

**From the Square dashboard (now supported, via webhook):**

- [ ] Issue a small refund directly in Square
- [ ] Within a few seconds, the order in Solidus shows the refund and its
      payment state changes
- [ ] The refund's reason reads "Refunded in Square"

This used to be the known gap -- a dashboard refund was invisible to Solidus and
the order went on reading as fully paid. `POST /square/webhooks` closes it. See
"Square refund webhook" below for the setup, which must be done in Square's
Developer Console before this check can pass.

---

## Known behaviour that looks wrong but is not

- **A partially refunded order shows `balance_due`.** The order total is
  unchanged while net payments have dropped, so Solidus reports a shortfall. It
  does not mean the customer owes money. Solidus's Customer Returns / RMA flow
  adjusts the order total properly; a direct payment refund does not.

- **Saved cards are not offered.** Square's browser tokens are single use, so
  customers re-enter their card each order. Storing cards is a separate feature
  (Square's Cards API) and a deliberate decision, not an oversight.

- **Admins cannot key in a card.** Square requires the card to be entered in the
  customer's own browser. Take the payment in Square directly and record it
  against the order as a Check payment with the receipt number.

---

## If something goes wrong mid-charge

The charge may have succeeded at Square even if the site showed an error. Always
check the Square dashboard before retrying, or the customer can be charged twice
— the idempotency key protects against a double-clicked button, not against a
retry after a crash.
