# Project status

Written 2026-08-20. Initial setup complete; the portal is deployed and behind a
password gate. What remains is launch work, not architecture.

## Live

<https://nsb-wholesale.onrender.com> — gated by `SITE_PASSWORD` (currently
`biscuits`). Remove that env var in Render to open the site.

Admin at `/admin/login`. Customers claim accounts at `/claim`.

## Done and verified

| Area | State |
|---|---|
| Hosting | Render, Docker, auto-deploy from `main` |
| Database | PostgreSQL 17, `basic-256mb` |
| Image storage | Blobs in PostgreSQL (`active_storage_db`), so `pg_dump` covers them |
| Catalog | 41 products, 30 images, idempotent import |
| Customers | 360 accounts, 53 addresses, no usable passwords by design |
| Account claim | Email-verified, built on Devise `:recoverable` |
| Email | Google Workspace OAuth2 SMTP, DKIM + SPF passing |
| Payments | Square, **sandbox only** — all four verifications passed |
| Fulfilment | ShipStation V1, pushes to store 104793, decoupled from checkout |
| CI | GitHub Actions: specs, Zeitwerk, Brakeman |
| Monitoring | Sentry, production only, PII filtered |
| Tests | 351 (excluding system specs) |

## Deliberately deferred

**Durable job queue.** ActiveJob is on `:async` — jobs live in process memory
and are lost on restart. Affects order confirmation emails and ShipStation
pushes; both have manual recovery (`nsb:shipstation:repush`, admin resend).
CLAUDE.md says not to add job infrastructure unasked. Revisit if an email is
ever lost, or if volume grows.

**Render database backups.** Confirm what `basic-256mb` includes. This database
holds 360 customers, every order, and all product images.

## Next: launch work

1. **Square production** — swap the four `SQUARE_*` vars, set
   `SQUARE_ENVIRONMENT=production`, then work through `docs/SQUARE_GO_LIVE.md`
   with a real small-dollar order. The store cannot take a real card until this
   is done.
2. **Custom domain** — DNS at SiteGround (nameservers are SiteGround, registrar
   is IONOS), plus `APP_HOST` and `STORE_URL` updated so email links match.
3. **11 products have no image** in the B2BWave export.
4. **Historical orders** — 1,154 line items still in the spreadsheet, undecided.
   The old Handshake wholesale history may already be in ShipStation, in which
   case importing them into Solidus may be unnecessary.

## Known quirks, so they are not rediscovered

- A partially refunded order shows `balance_due`. Expected: the order total is
  unchanged while payments dropped. Not money owed by the customer.
- A refund issued in the **Square dashboard** does not reach Solidus — no
  webhook. Refund from Solidus admin, or ask for the webhook to be built.
- `app/assets/builds/tailwind.css` and `public/assets` are gitignored. A stale
  `public/assets` makes local specs pass on assets CI does not have; CI builds
  Tailwind explicitly for this reason.
- Run `source ~/.rvm/environments/ruby-3.4.2` before any `bin/rails` — another
  Rails app on this machine uses Ruby 3.1.6. The `nsb_wholesale` shell function
  handles this.
- 2 quantity-promotion system specs fail against Solidus's legacy promotions
  engine. No promotions are configured, so the code is dormant.

## Operator commands

```
bin/rails nsb:monitoring:status          # Sentry, mail, ShipStation, Square at a glance
bin/rails nsb:monitoring:test            # send a test error to Sentry
bin/rails nsb:shipstation:status         # push state of recent orders
bin/rails 'nsb:shipstation:repush[R123]' # re-push after an outage
bin/rails nsb:import:catalog             # re-import products (safe to re-run)
bin/rails nsb:import:store               # store name/url/from-address
```
