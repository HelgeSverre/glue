---
id: TASK-28
title: Evaluate and add browser-automation providers
status: To Do
assignee: []
created_date: "2026-04-19 05:30"
updated_date: "2026-04-20 00:05"
labels:
  - web
  - browser
  - provider
milestone: m-0
dependencies: []
documentation:
  - website/docs/advanced/browser-automation.md
  - cli/lib/src/web/browser/providers/
priority: medium
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->

Glue ships with **seven** browser backends today: `local`, `docker`,
`browserbase`, `browserless`, `steel`, `anchor`, and `hyperbrowser`. All
implement `BrowserEndpointProvider`
(`cli/lib/src/web/browser/browser_endpoint.dart`) and plug in via
`BrowserManager`.

This task enumerates additional providers, evaluates them, and ships
adapters for the ones we keep. Scope was trimmed after research (see
Notes) — the remaining v1 work is **two** providers (Cloudflare + Bright
Data), not the full original list.

## Scope — accept (still pending)

Ship adapters for both, behind `<FeatureStatus status="experimental" />`.

| Provider                                             | Category                       | Why                                                                                                                                                                                                                                                                  | Adapter complexity                                                                                                                                                                                                                                      |
| ---------------------------------------------------- | ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Cloudflare Browser Rendering** (aka "Browser Run") | First-party platform browser   | Cheapest backend in class (~$0.09/browser-hour), free tier on Workers Free (10 min/day). CDP endpoint shipped 2026-04-10. Auth is a single API token; no POST-to-create — the WS URL itself provisions the session. Simpler than every other cloud provider we have. | **TRIVIAL** — synthesize a `wss://api.cloudflare.com/client/v4/accounts/{ACCOUNT_ID}/browser-rendering/devtools/browser?keep_alive=600000` URL with `Authorization: Bearer <token>` on the upgrade. No session DELETE; closing the WS ends the session. |
| **Bright Data Scraping Browser**                     | Unblocking / residential-proxy | Reference product for residential-IP + anti-bot automation. Fulfills the "scraping unblocker" category of Glue's browser story.                                                                                                                                      | **TRIVIAL** — fixed `wss://brd-customer-<ID>-zone-<ZONE>:<PASSWORD>@brd.superproxy.io:9222` URL with HTTP Basic in userinfo. No API calls, no teardown. Even thinner than Anchor.                                                                       |

## Shipped in this task

- **Hyperbrowser** — shipped 2026-04-20 (this session). Original verdict
  was Defer ("duplicates Browserbase / Steel / Anchor, no sharp
  daylight"), but the adapter proved trivial against the settled
  `BrowserEndpointProvider` pattern, and giving users one more
  agent-focused cloud option has low downside. Registered as
  `BrowserBackend.hyperbrowser` with config field
  `hyperbrowser_api_key` and env var `HYPERBROWSER_API_KEY`. Experimental
  status. Uses `POST /api/session` / `PUT /api/session/{id}/stop` with
  `x-api-key` auth.

## Scope — defer, with reasons

Captured here so the decision doc (AC #1) is satisfied inline.

| Provider                                     | Verdict      | Reason                                                                                                                                                                                                                                                                                                                                                                                                                       |
| -------------------------------------------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Scrapybara**                               | Defer        | Its unique value (full desktop sandbox alongside the browser) overlaps with the planned cloud-runtime workstream (TASK-26). Surface it there as a runtime, not as a parallel browser backend — don't double-ship the concept.                                                                                                                                                                                                |
| **Zyte API / Smart Browser**                 | Defer (hard) | No CDP endpoint. The product is a REST `actions[]` API, not a `wss://`. Adding it would be an adapter-shape rewrite, and it duplicates Bright Data's scraping role anyway.                                                                                                                                                                                                                                                   |
| **Apify Scraping Browser**                   | Defer (hard) | Wrong shape. Apify is an Actor platform, not a CDP endpoint — their own docs recommend bringing a Bright Data CDP URL _into_ an Actor. Not a `BrowserEndpointProvider` fit.                                                                                                                                                                                                                                                  |
| **Oxylabs Unblocking Browser**               | Hold         | The only other provider on the list that ships a real residential-proxy + CDP browser. Legitimate slot-2 redundancy vs. Bright Data if we ever want it, but defer for now — one unblocking backend covers the user story.                                                                                                                                                                                                    |
| **Playwright local** (`local-playwright`)    | Defer        | No maintained Playwright binding on pub.dev. Playwright's Firefox/WebKit use the Playwright protocol, not CDP — so "add Playwright for multi-engine coverage" is structurally incompatible with Glue's CDP-only `BrowserEndpoint` contract. Getting there needs a protocol abstraction layer (multi-week refactor), not an adapter. Track multi-engine as a separate concern, preferably via WebDriver BiDi when that lands. |
| **e2b browser**, **Modal + headless Chrome** | Defer        | Belong in the cloud-runtime workstream (TASK-26), surfaced via the runtime API, not as browser backends.                                                                                                                                                                                                                                                                                                                     |

## Work, per accepted provider

1. **Adapter.** `CloudflareProvider` and `BrightDataProvider` under
   `cli/lib/src/web/browser/providers/`. `hyperbrowser_provider.dart` is
   the closest template (auth → build endpoint → return). Bright Data is
   even simpler — no HTTP client needed.
2. **Config.** Extend `BrowserConfig` with:
   - Cloudflare: `cloudflare_account_id`, `cloudflare_api_token`,
     optional `cloudflare_keep_alive_ms` (default 600000).
   - Bright Data: `brightdata_customer_id`, `brightdata_zone`,
     `brightdata_zone_password`.
     Update `docs/reference/config-yaml.md`.
3. **Registration.** Wire into the switch in
   `cli/lib/src/core/service_locator.dart`.
4. **Tests.** `isConfigured`, URL construction, one mocked happy-path
   provisioning test. No live network.
5. **Docs.** Add rows to the backends table in
   `website/docs/advanced/browser-automation.md`. For Bright Data,
   **explicitly document** the two gotchas:
   - Per-GB billing — unpredictable cost on media-heavy pages (~30× swing
     between a 500 KB and 3 MB page for identical work).
   - One `page.goto()` per session — subsequent navigations require a
     fresh WS connection.
6. **Status label.** Add both to `website/data/feature-status.yaml` as
   `experimental`.
7. **Credentials.** Document required env vars in the Configuration page
   under Credentials.

## Notes

- **Research date: 2026-04-20.** Scope was trimmed from ~10 candidates to
  2 after evaluating CDP-endpoint availability, adapter complexity,
  pricing, and overlap with existing providers. Full per-provider
  verdicts are in "Scope — defer" above. Hyperbrowser was
  reclassified from defer to ship during the same session.
- Cloudflare's CDP endpoint is ~10 days old as of this writing
  (announced 2026-04-10). The underlying Browser Rendering platform has
  been GA since mid-2025, but monitor for rough edges on the CDP path
  specifically.
- Keep `BrowserEndpointProvider` minimal. If a provider ever needs a
  bespoke session lifecycle (snapshots, retries, branched sessions),
  consider whether that's a separate capability rather than pushing it
  into every adapter.
- Coordinate with TASK-26 (runtime boundary). Runtimes that naturally
  host a browser (e2b, Modal, Scrapybara's desktop) should surface the
  browser via the runtime API — not as a parallel browser backend.
- If residential-proxy redundancy becomes a requirement, Oxylabs is the
cleanest second-source option (CDP-native, similar shape to Bright
Data). File a follow-up task then — don't add it speculatively.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->

- [x] #1 Decision doc committed: accept/defer recorded for every candidate in the Scope-Defer section (inline in description).
- [ ] #2 Cloudflare Browser Rendering provider shipped behind experimental status.
- [ ] #3 Bright Data Scraping Browser provider shipped behind experimental status, with per-GB cost and single-navigation caveats documented.
- [x] #4 Playwright local decision (defer) recorded in description — closed.
- [ ] #5 Backends table on /docs/advanced/browser-automation lists both new providers with honest status labels.
- [ ] #6 feature-status.yaml + consistency checker pass.
- [ ] #7 Per-provider credentials documented in the Configuration page (cloudflare_account_id + cloudflare_api_token; brightdata_customer_id + brightdata_zone + brightdata_zone_password).
<!-- AC:END -->
