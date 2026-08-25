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
| Tests | 368 (excluding system specs) |

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

Verify it after a deploy from the Render service Shell:

```
bin/rails nsb:monitoring:status
```

Expect `Running commit` to match what you pushed, `adapter: SolidQueue`, and
`workers running: Dispatcher, Supervisor(async), Worker`. If `Running commit`
is behind, the deploy has not finished. If workers say `NONE`, the code is live
but `SOLID_QUEUE_IN_PUMA` did not reach the service.

Check on it with `bin/rails nsb:monitoring:queue` (also included in
`nsb:monitoring:status`). It reports the adapter in use, whether anything is
actually draining the queue, pending and failed counts, and how old the oldest
pending job is. If it says NOTHING IS DRAINING THE QUEUE, `SOLID_QUEUE_IN_PUMA`
is missing from the Render service — nothing is lost, and the backlog runs as
soon as a worker starts.

## Next: launch work

1. **Square production** — swap the four `SQUARE_*` vars, set
   `SQUARE_ENVIRONMENT=production`, then work through `docs/SQUARE_GO_LIVE.md`
   with a real small-dollar order. The store cannot take a real card until this
   is done.
2. **Custom domain** — `wholesale.newsouthbotanicals.com`. Render side is
   prepared; see "Custom domain" below for the order of operations.
3. **11 products have no image** in the B2BWave export.
4. **Historical orders** — 1,154 line items still in the spreadsheet, undecided.
   The old Handshake wholesale history may already be in ShipStation, in which
   case importing them into Solidus may be unnecessary.

## Custom domain

`wholesale.newsouthbotanicals.com`. The retail WordPress site owns the apex
`newsouthbotanicals.com` (an A record to SiteGround at 34.174.207.184), so the
portal takes a subdomain. Nameservers are SiteGround's (`ns1/ns2.siteground.net`),
registrar is IONOS — DNS records are edited at **SiteGround**, not IONOS.

`render.yaml` declares the domain, so a Blueprint sync creates it on the Render
side. That is only step one; the rest is DNS and cannot be done from the repo.

**Order of operations. Do not reorder — steps 4 and 5 are what send customers a
working link rather than a broken one.**

1. Deploy, so Render picks up the `domains:` entry. Render Dashboard → the
   `nsb-wholesale` service → Settings → Custom Domains should then list
   `wholesale.newsouthbotanicals.com` as unverified, with the DNS target to use.
2. At **SiteGround** (Site Tools → Domain → DNS Zone Editor) add a CNAME:
   - Name/host: `wholesale`
   - Value: `nsb-wholesale.onrender.com`
   Leave the apex and `www` records alone — they point at the retail site.
3. Back in Render, click **Verify**. Render issues the TLS certificate once the
   record resolves; propagation can take a few minutes to a few hours. Confirm
   from a laptop: `dig +short wholesale.newsouthbotanicals.com` returns Render
   addresses, then `curl -sI https://wholesale.newsouthbotanicals.com/up`
   returns 200 with no certificate warning.
4. **Only once step 3 passes**, point the app at the new host: set `APP_HOST`
   and `STORE_URL` to `wholesale.newsouthbotanicals.com` in the Render
   dashboard, redeploy, then run `bin/rails nsb:import:store` from the Render
   shell so `Spree::Store#url` matches.
5. Verify with `bin/rails nsb:monitoring:status`. The Domain section should show
   both values agreeing, and say `on the custom domain`.

**The trap.** Both settings already DEFAULT to
`wholesale.newsouthbotanicals.com` in code (`config/environments/production.rb`
and `Nsb::StoreConfigurator`). Leaving them unset is therefore not neutral — it
selects the new domain. Keep them explicitly set to `nsb-wholesale.onrender.com`
until step 4, or emails sent in the meantime will link somewhere that does not
resolve.

The `onrender.com` address keeps working after the cutover; adding a custom
domain does not retire it. That is what makes backing out of step 4 safe.

Host authorization (`config.hosts`) is deliberately left off. Emailed links are
built from `Spree::Store#url` and `APP_HOST`, never from the request's `Host`
header, so the usual Host-header poisoning payoff is not available here. Turning
it on is available hardening, but it can 403 the whole site if the health check
is not excluded — not something to bundle into a DNS cutover.

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
bin/rails nsb:monitoring:status          # Sentry, mail, ShipStation, Square, jobs at a glance
bin/rails nsb:monitoring:queue           # background job queue health on its own
bin/rails nsb:monitoring:test            # send a test error to Sentry
bin/rails nsb:shipstation:status         # push state of recent orders
bin/rails 'nsb:shipstation:repush[R123]' # re-push after an outage
bin/rails nsb:import:catalog             # re-import products (safe to re-run)
bin/rails nsb:import:store               # store name/url/from-address
```
