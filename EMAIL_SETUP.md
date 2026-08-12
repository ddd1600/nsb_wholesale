# EMAIL_SETUP.md — Transactional Email Handoff

> Companion doc to `CLAUDE.md`. Scope: outbound transactional email only.
> Written 2026-08-12 at the point of handoff to Claude Code.
> `CLAUDE.md` remains the authority on everything else — do not edit it based
> on this file.

---

## The decision

Transactional email sends through **Google Workspace (Gmail) SMTP** from
`connect@newsouthbotanicals.com`, not through a dedicated ESP.

**Why, so you don't re-litigate it:**

1. Volume is tiny — roughly one order per day. Gmail's limits are irrelevant here.
2. **CBD/hemp is a restricted category at many ESPs.** Mailchimp and others have
   terminated accounts over it. Sending through our own Workspace removes the
   risk of a provider shutting off order confirmations without warning.
3. The operator already pays for Workspace.

**Do not propose migrating to SendGrid, Mailgun, Postmark, or Resend.** The
tradeoffs were weighed and this was chosen deliberately.

## What we knowingly gave up

Gmail SMTP has **no delivery webhooks, no bounce API, and no suppression list.**
Bounces arrive as messages in the `connect@` inbox and the operator reads them
manually. At one order per day this is acceptable. Do not attempt to build
bounce-parsing infrastructure to compensate — it is not worth it at this scale.

---

## Configuration target

| Setting | Value |
|---|---|
| Host | `smtp.gmail.com` |
| Port | `587` (STARTTLS) |
| Auth | Google **App Password** (16 chars), NOT the account password |
| Username | `connect@newsouthbotanicals.com` |
| From | `connect@newsouthbotanicals.com` (same as auth account — deliberate) |

**Authenticating account and sending account are intentionally identical.** This
avoids Gmail's From-header rewriting entirely. An SMTP relay approach that
authenticates as one address and sends as another was considered and dropped as
unnecessary complexity.

**Plain username/password SMTP no longer works for Google Workspace** (Google
ended it May 2025). If auth fails, the answer is never "try the account
password." It is either a bad app password or an admin policy issue — surface
it, don't work around it.

---

## Manual setup state as of handoff

These are the operator's tasks, done outside the codebase. **Verify before
assuming any are complete.**

| Step | Status |
|---|---|
| DKIM key generated in Workspace Admin | ✅ Done |
| DKIM TXT record published at IONOS (`google._domainkey`) | ✅ Done |
| DKIM record propagated / verified via dig | ⏳ In progress — IONOS quotes up to 1hr, sometimes longer for TXT |
| "Start authentication" clicked in Admin console | ⏳ Pending propagation |
| SPF record confirmed to include `_spf.google.com` | ❓ Not yet verified — check for an existing record before adding a second (two SPF records is a hard failure) |
| 2-Step Verification enabled on `connect@` | ⏳ Not yet done |
| App Password generated | ⏳ Not yet done — blocked on 2SV |

**DNS host is IONOS.** Domain is `newsouthbotanicals.com`.

Verification command once propagation completes:

```
dig TXT google._domainkey.newsouthbotanicals.com +short
```

Note the operator's ISP resolver may cache stale results; querying IONOS's
authoritative nameservers directly is more reliable.

---

## Credentials — hard rules

- The app password is **never** committed, never written to a file in the repo,
  never logged, never echoed in terminal output.
- It lives **only** in Render's environment variables.
- Reference it as `GMAIL_APP_PASSWORD` (or similar) via `ENV`. Never inline.
- If you need it to test, ask the operator to set it in the environment. Do not
  ask him to paste it into chat.

---

## Build requirements

### 1. Email failure must never break checkout

**This is the most important rule in this document.**

An SMTP call inside the order transaction means a transient Gmail failure can
roll back an order that Square has **already charged**. That is a real-money bug
and the operator will not catch it by reading code.

Use `deliver_later`, or at minimum rescue and log so the order commits
regardless of mail outcome. The order is the source of truth; the email is a
notification. Same principle as the ShipStation rule in `CLAUDE.md`.

### 2. Wrap sending in a thin abstraction

Cheap insurance. If Google changes auth rules again — which they have twice
recently — swapping providers should be a config change, not a rewrite. Do not
scatter raw SMTP settings through mailers.

### 3. Development must not send real mail

Use `letter_opener` (or equivalent) in development. Production SMTP credentials
must not be reachable from the dev environment. Keep the two environments'
credentials fully separate, per `CLAUDE.md`.

### 4. Keep this stream strictly transactional

Order confirmations, shipping notifications, password resets. **No promotional
or bulk sending through this account.** That is both a Workspace terms issue and
a domain-reputation issue — and our domain reputation is now what carries the
order confirmations.

---

## Definition of done

Do not report this complete on passing tests alone. Produce a checklist for the
operator to verify manually:

1. A real test send from the app arrives at an external Gmail address.
2. In that message: **Show original** → headers show `dkim=pass` **and**
   `spf=pass`.
3. The From address displays as `connect@newsouthbotanicals.com` and has not
   been rewritten.
4. **Simulate an SMTP failure** (bad credentials or blocked port) and confirm an
   order still completes and persists. This is the failure mode that costs money.

---

## Open question to resolve early

If **App Passwords turn out to be unavailable** on the Workspace account — either
disabled by admin policy or restricted by Google — the fallback is OAuth2 /
XOAUTH2, which is a significantly larger build (tokens expire roughly hourly and
need proactive refresh).

**Confirm the app password exists and works before building against it.** If it
doesn't, stop and tell the operator rather than scaffolding OAuth2 unprompted —
that changes the shape of the work and he should decide.
