# CLAUDE.md — Wholesale Ordering Portal

## What this project is

A B2B wholesale ordering portal for a CBD oil company. Existing wholesale
customers log in, browse the product catalog, and place orders.

**Scale is very small.** Roughly one customer per day; never more than about
three concurrent users. Do not build for scale. Do not add caching layers,
background job infrastructure, CDNs, queues, or horizontal-scaling concerns
unless explicitly asked. Simplicity beats throughput here every time.

This is a **low-priority project**. Prefer the boring, well-trodden path over
the clever one. If there is a conventional Solidus/Rails way to do something,
do it that way even if you can think of something better.

## Stack

- **Ruby on Rails**
- **Solidus** for the storefront, catalog, cart, checkout, and admin
- **Square** for credit card processing
- **ShipStation** for fulfillment (custom API integration)
- **PostgreSQL**
- **Render** for hosting, with Git push-to-deploy

## Non-negotiable constraints

1. **Square is the payment processor. Do not propose or scaffold Stripe,
   Braintree, PayPal, or any alternative.** Solidus documentation and most
   community extensions assume Stripe — ignore that pull. If you hit a wall,
   surface the problem rather than quietly substituting a different processor.
2. **Do not hand-roll the store.** Users, products, variants, carts, orders,
   line items, shipments, and address management all come from Solidus. If you
   find yourself writing a `Product` model or a shipping-address form from
   scratch, stop — you have gone off the rails (pun accepted).
3. **Card data never touches our server.** Use Square's Web Payments SDK in the
   browser to tokenize the card, and send only the resulting token to the
   backend. Never accept, log, or persist raw PAN, CVV, or expiry.

---

## The operator's working style — read this carefully

The person running this project is an experienced Rails developer, but **will
not be reading your code line by line and will not be learning Solidus
internals.** He is deliberately hands-off. That has direct consequences for how
you should work:

- **Work in small, verifiable steps.** One coherent change at a time. Do not
  generate the entire store in a single pass.
- **Write tests and actually run them.** Code that has not been executed is not
  done. Prefer a small honest test over a large aspirational one.
- **After each step, state in plain English what you changed and what a human
  would need to click or do to confirm it works.** Assume the reader has not
  read the diff.
- **Flag uncertainty out loud.** If you guessed at a Solidus convention or a
  Square API detail, say so explicitly rather than presenting it as settled.
- **Never silently work around a blocker.** Stubbing, faking, or hardcoding a
  value to make a test pass is worse than reporting failure. Say what broke.

### The self-review limit — be honest about it

Self-review catches errors of *correctness* (does it run, does the test pass).
It is much weaker at errors of *intent* (it runs perfectly and does the wrong
thing). Do not let a green test suite convince you a payment flow is right.

---

## 🔴 Payment code: the highest-stakes area

The Square integration is where a bug costs real money and real trust. Treat it
differently from everything else.

**Rules:**

- Build the Square payment method against Square's **official Ruby SDK**
  (`square.rb`) and Solidus's custom payment gateway extension points. Do not
  pull in an unmaintained community Square extension without flagging it first.
- **An order is only marked paid after Square confirms the charge succeeded.**
  Never mark an order paid optimistically, never mark it paid on tokenization,
  never mark it paid in a `rescue` block. This specific mistake is the one most
  likely to slip past a passing test suite.
- Handle the unhappy paths explicitly and separately: declined card, network
  timeout mid-charge, duplicate submission, partial refund, full refund.
- Use Square's **Sandbox** environment for all development and automated
  testing. Read credentials from environment variables — never commit keys.
- Implement idempotency on charge creation so a double-clicked checkout button
  cannot double-charge a customer.

**When payment work is complete, do not call it done. Instead, produce an
explicit checklist for the operator to verify with a real, small-dollar live
transaction**, covering at minimum:

1. A successful charge appears in the Square dashboard for the right amount.
2. The order is marked paid in Solidus *only* after that confirmation.
3. A declined card leaves the order unpaid and shows the customer a clear error.
4. A refund issued from Square (or from Solidus) reconciles correctly on both sides.

The same "verify it for real" standard applies to **anything touching customer
data or authentication**. Everything else — product listings, styling, address
forms, admin tweaks — is low blast radius; move fast there.

---

## Solidus conventions to follow

- **Solidus is a Rails engine.** Its models, controllers, and views live inside
  the gem, not in `app/`. Do not edit gem source.
- **Customize via overrides/decorators**, using Solidus's supported override
  mechanism to reopen and patch its classes. Keep these in a consistent,
  obvious location and keep each one small and commented with *why*.
- **Respect the order state machine** (`cart → address → delivery → payment →
  complete`). The Square step must slot into the `payment` state properly rather
  than bypassing the machine.
- Store configuration belongs in the Spree initializer, not scattered through
  the app.
- Seed data and catalog population should be idempotent and re-runnable.

## ShipStation integration

Built custom against ShipStation's REST API — there is no plugin and none is
wanted. Keep it decoupled from checkout: an order should complete successfully
even if ShipStation is briefly unreachable, with the fulfillment push retried or
queued rather than blocking the customer. Log failures somewhere the operator
will actually see them.

## Catalog migration

Product data (names, descriptions, prices, images) is being brought over from the
existing wholesale site. Prefer a clean structured export (e.g. a Square catalog
export) over scraping the front end when one is available. If scraping, write the
results to an intermediate file for review before importing — do not scrape
straight into the production database.

## Deployment

- Render, with Git push-to-deploy.
- Maintain a clear separation between development and production: separate
  databases, separate Square credentials (Sandbox vs. Production), separate
  ShipStation credentials.
- **Never run destructive commands against the production database.** If a
  migration is risky, say so and stop.
- Secrets live in Render's environment variables. Nothing sensitive in the repo.

## Styling

Goal is "professional-ish without much effort." Do not embark on a custom
design system, and do not spend cycles on bespoke CSS.

- **Start from the stock Solidus starter frontend**, which ships on Hotwire
  (Turbo + Stimulus) and is styled with **Tailwind CSS**. It already looks
  clean and modern out of the box.
- **First pass is minimal:** drop in the logo, set a small color palette, adjust
  spacing/typography lightly. For a wholesale portal with a handful of B2B
  customers, that is very likely enough — ship it before doing more.
- **If and only if the default feels too plain,** pull in a prebuilt Tailwind
  component library rather than hand-building components. Prefer the free
  **DaisyUI** (or Flowbite) — since the storefront is already Tailwind, these
  slot in with minimal work. Tailwind UI is the paid, higher-polish option if
  the operator asks for it.
- **Ignore older Solidus tutorials that reference a Bootstrap-based frontend.**
  Tailwind is the current direction; do not reintroduce Bootstrap or SCSS
  frameworks alongside it.
- Styling is **low blast radius** — move fast here. Do not apply the
  payment-code level of caution to visual work.
