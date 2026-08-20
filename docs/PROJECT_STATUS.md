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
| Background jobs | Solid Queue in the primary database, supervisor runs inside Puma |
| CI | GitHub Actions: specs, Zeitwerk, Brakeman |
| Monitoring | Sentry, production only, PII filtered |
| Tests | 359 (excluding system specs) |

## Deliberately deferred

**Render database backups.** Confirm what `basic-256mb` includes. This database
holds 360 customers, every order, and all product images.

## Background jobs

Solid Queue, added 2026-08-20, replacing the `:async` adapter that lost every
pending job on restart or redeploy. Two things run out of band after the
customer has already paid — the order confirmation email and the ShipStation
push — so a lost job was silent and only surfaced as a customer who never got
their email.

- Jobs are rows in the **primary** database (`solid_queue_*` tables), not a
  separate queue database. One Render database, one `pg_dump`, no extra cost.
- The supervisor runs **inside the Puma process**, in `:async` mode, enabled by
  `SOLID_QUEUE_IN_PUMA=true` in `render.yaml`. No second Render service to pay
  for, and no forked copy of the app to fit into the starter plan's 512MB.
- If `SOLID_QUEUE_IN_PUMA` is ever unset, jobs are still enqueued but nothing
  runs them. They pile up in `solid_queue_ready_executions` rather than
  vanishing, so the failure is recoverable — but it is silent until noticed.
- `config/queue.yml` sizes it: one worker, 3 threads, polling every second.
  `config/recurring.yml` clears finished jobs hourly.
- `config/database.yml` sets the connection pool above `RAILS_MAX_THREADS`
  because the job threads and Puma's request threads share one pool.
- Development still uses `:async` deliberately — no worker to remember to start.
  To exercise the real queue locally, run `bin/jobs` alongside the server.

Inspect the queue: `SolidQueue::Job.where(finished_at: nil).count` for pending
work, `SolidQueue::FailedExecution.all` for jobs that gave up.

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
