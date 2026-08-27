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

## Who can see what, and how someone gets an account

The storefront is half-open. A visitor with no account can see the catalog --
product names, descriptions and photos -- so a prospect can decide whether
applying is worth their time. Everything commercial requires an account:

| Signed out | Signed in |
|---|---|
| Welcome page at `/`, catalog, product pages | Catalog with wholesale pricing |
| No prices anywhere, including Solidus's price-range filter | Cart, checkout, order history |
| No add-to-cart; a prompt to sign in or apply | |

`ApplicationHelper#show_wholesale_prices?` guards every view that renders a
price; `Nsb::RequiresWholesaleAccount` closes the cart, checkout, orders and
coupon controllers. Both halves matter: hiding prices while leaving the cart open
would let someone read the same numbers back out of it.

**The price assertions in `spec/requests/wholesale_gate_spec.rb` scan rendered
HTML, not helpers.** That is deliberate. Prices reach the page through several
partials plus a Solidus filter facet, and a guard added to four of five leaks
nothing visible until a competitor reads the fifth. The spec strips tags without
a separator, because Solidus renders money as split spans -- a regex over raw
HTML matches nothing and the assertion passes for the wrong reason.

### Two ways in

**Existing customers** (the 360 migrated from B2BWave) claim the account already
created for them: `/claim`, email verified, Devise reset token, set a password.
Unchanged from before, except that finishing it now emails the operator --
`spree_users.nsb_activated_at` makes that fire exactly once, so a later forgotten
password is not reported as another activation.

**Everyone else** applies at `/apply`. The form is all-required, including phone
and retail licence state and number, because that is what the operator vets on.
Submitting emails the operator with a link to review it. An applicant whose email
already has an account is sent to `/claim` instead -- with 360 migrated accounts,
that mistake is likely, and a duplicate is work to reconcile.

Nothing creates a `Spree::User` until approval. An unvetted applicant never
appears in the customer list, the admin user search, or any customer count.

### Reviewing applications

Solidus admin -> `/admin/wholesale_applications`. Inherits Solidus's own admin
authentication, so it is the same login, not a second one.

- **Approve** creates the account and emails them a link to set a password --
  the same page migrated customers land on.
- **Decline** is silent by the operator's choice: it clears the pending list and
  the applicant hears nothing.

Both are one-way; an application that has been reviewed cannot be reviewed again.

`OPERATOR_NOTIFICATION_EMAILS` (comma-separated) sets who gets the notifications,
defaulting to david@newsouthbotanicals.com and ddd1600@gmail.com. Changeable in
Render without a deploy.

**`SITE_PASSWORD` must be removed before any of this is reachable.** The gate is
Rack middleware that blocks everything except `/up`, so while it is set no
applicant can reach the welcome page at all.

## Catalog pipeline, and the order it runs in

The catalog is built from committed files in `db/import_data/` by four steps that
must run in this order. Each is safe to re-run; running them out of order is what
goes wrong.

```
bin/rails nsb:import:catalog       # 1. products from the B2BWave export
bin/rails nsb:import:consolidate   # 2. fold pack sizes into variants
bin/rails nsb:images:import        # 3. product photos from the public site
bin/rails nsb:images:lab_tests     # 4. current COAs, above the ones they supersede
bin/rails nsb:images:warm          # 5. pre-generate variants (see the memory section)
```

**Why the order matters.** Step 2 renames products and moves SKUs off the master,
so step 1 must have created them first. Step 3 reorders every gallery it touches,
putting manifest images first — so step 4 has to come after it, or the new
certificates get pushed back below the old ones. Step 5 is last because steps 3
and 4 are what add the images it warms.

**The data files, and what each is for:**

| File | Purpose |
|---|---|
| `products.json` | Faithful copy of the B2BWave export. Do not hand-edit. |
| `product_overrides.json` | Field-level corrections to known-bad source rows, keyed by `b2b_product_id`. |
| `product_variants.json` | Pack sizes folded into one product with variants. First variant listed is the storefront default. |
| `scraped_images/manifest.json` | Which photos each SKU gets, and in what order. |
| `lab_tests/manifest.json` | Which COA belongs to which product, and which older lab tests it supersedes. |

**Pack sizes are variants, not separate products.** B2BWave had no variant
concept, so Delta 8 Gummies, Supreme Formula Gummies and THC Free Gummies each
arrived as two products. `product_variants.json` folds them into one page with a
Pack Size picker, defaulting to the larger pack. The folded-away products are
discontinued rather than deleted — order history references them — and their
master SKUs are cleared, because Solidus enforces SKU uniqueness across every
variant that is not soft-deleted and the new variant now claims that SKU.

**Lab tests are images, converted from PDF.** The operator supplies COAs as
two-page PDFs; Solidus galleries hold images and Active Storage will not build
variants of a PDF. Both pages are kept. New certificates are placed directly
above the lab test they supersede, and the old image is kept rather than deleted
— a customer may hold a link to it.

## Memory ceiling, and the image-variant rule

The web service is Render's `starter` plan: **512MB and 0.5 CPU**, shared by
Puma and the Solid Queue supervisor. Solidus is not a small application and that
ceiling is real, not theoretical.

**What happened on 2026-08-27.** Product images were imported without
pre-generating their variants, so Active Storage built each variant inline,
inside the web request, using libvips. `/admin/stock_items` took 9.9 seconds,
storefront product pages took 4-5 seconds, and the instance OOM-killed itself
repeatedly — a 502 to the browser and several minutes down each time. The tell
in the logs is an `ActiveStorage::AnalyzeJob` taking 18,007ms against a normal
10-200ms, immediately before `==> Instance restarted`.

**The rule: run the variant warmer after any image import.** Without it, the
first visitor to each page generates every variant and waits — and on this
instance may take the whole service down instead.

```
bin/rails nsb:images:import
bin/rails nsb:images:warm     # NOT optional
```

**Warming cannot be done from the Render shell.** It needs more memory than the
instance has spare, so it dies within seconds, takes the whole instance with it,
and you lose the shell output. Because blobs live in PostgreSQL rather than on
disk, run it from a laptop against the production database instead — the
variants land in the same `db` service the live site reads, because Active
Storage creates variant blobs with the parent blob's `service_name`.

Get the **External** Database URL from Render (the internal one only resolves
inside Render), then:

```
DATABASE_URL='<external url>' bin/rails runner 'Spree::Image.order(:id).pluck(:id).each { |id| img = Spree::Image.find(id); next unless img.attachment.attached?; %i[mini small product large].each { |s| img.attachment.variant(s) }; print "."; $stdout.flush }'
```

This only ever creates rows — variant blobs and variant records. It modifies and
deletes nothing. Safe to re-run; it skips what already exists. Check progress
with:

```
bin/rails runner 'puts "#{ActiveStorage::VariantRecord.count} of ~#{Spree::Image.joins(:attachment_attachment).count * 4}"'
```

**Other things that push against the ceiling.** The job worker runs on one
thread deliberately (`config/queue.yml`) for this reason. Bulk admin actions and
large imports are the other candidates. If this happens again and there is no
un-warmed image import to blame, the answer is the 2GB Render plan rather than
another workaround — this one is already at the end of what tuning can buy.

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
bin/rails nsb:import:consolidate         # fold pack sizes into variants
bin/rails nsb:import:store               # store name/url/from-address
bin/rails nsb:images:import              # attach product photos (safe to re-run)
bin/rails nsb:images:lab_tests           # attach current COAs above the older ones
bin/rails nsb:images:warm                # pre-generate variants -- REQUIRED after an import
```
