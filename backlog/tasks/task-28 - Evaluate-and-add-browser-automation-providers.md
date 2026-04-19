---
id: TASK-28
title: Evaluate and add browser-automation providers
status: To Do
assignee: []
created_date: '2026-04-19 05:30'
updated_date: '2026-04-19 04:02'
labels:
  - web
  - browser
  - provider
dependencies: []
documentation:
  - website/docs/advanced/browser-automation.md
  - cli/lib/src/web/browser/providers/
priority: medium
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Glue ships with five browser backends today: `local`, `docker`, `browserbase`,
`browserless`, and `steel`. All implement `BrowserEndpointProvider`
(`cli/lib/src/web/browser/browser_endpoint.dart`) and plug in via
`BrowserManager`.

This task enumerates additional providers worth adding and implements
adapters for the ones we keep. We cover the full usefulness spectrum — from
first-party platform browsers to residential-proxy + anti-bot products —
since Glue's browser tool is the generic substrate and users pick the
backend that fits their workload.

## Candidates

Ranked by expected payoff for Glue users.

### Likely yes — standard cloud browsers

| Provider | Hosted by | Why add it | Notes |
| -------- | --------- | ---------- | ----- |
| **Cloudflare Browser Rendering** | Cloudflare | First-party platform browser on a network many users already deploy to. Simple REST + WS surface. Good first add — smallest new surface area. | Region coverage = CF edge. |
| **Hyperbrowser** | hyperbrowser.ai | Agent-focused entrant with a clean session API; positioning close to Steel and Browserbase. | Check pricing + SLA before promoting beyond `experimental`. |
| **Anchor Browser** | anchorbrowser.io | Agent-focused; built for LLM agents. Persistent sessions. | Newer company — evaluate reliability. |
| **Scrapybara** | scrapybara.com | Agent-first browser + full desktop sandbox on the same API. Interesting bridge to the planned cloud-runtime work. | Overlaps with TASK-26 (runtime boundary) — coordinate. |

### Likely yes — scraping / unblocking

Backends whose value prop is residential IPs, fingerprint spoofing, and/or
CAPTCHA handling. Users in scraping, market-research, price-monitoring, and
data-collection workflows expect these.

| Provider | Hosted by | Why add it | Notes |
| -------- | --------- | ---------- | ----- |
| **Bright Data Scraping Browser** | Bright Data | The reference product for residential-proxy + anti-bot automation. Widely used. | Has a CDP endpoint, so the adapter is basically an auth + WS wrapper. |
| **Zyte API / Smart Browser** | Zyte | Long-standing scraping infra (Scrapy authors). Strong documentation, stable API. | Check CDP compatibility vs. their HTTP API. |
| **Apify Scraping Browser** | Apify | Popular for data extraction; generous free tier; large actor ecosystem. | Straightforward WS adapter. |
| **Oxylabs Web Unblocker / Scraper API** | Oxylabs | Residential + datacenter proxy networks. Competes with Bright Data. | Evaluate which of their products actually expose a CDP endpoint vs. only HTTP. |

### Engine / local option

| Item | Why | Notes |
| ---- | --- | ----- |
| **Playwright-based local provider** | Puppeteer is Chromium-only; Playwright covers Chromium + Firefox + WebKit. Lets us test Glue against all three engines locally. | Adds a Dart dep (`playwright_dart` or a CDP-direct variant). Ship as `local-playwright`; eventually consider replacing `local`. |

### Probably through the runtime API, not as a browser backend

| Provider | Why | Notes |
| -------- | --- | ----- |
| **e2b browser (via e2b sandbox)** | Aligns with TASK-26 cloud-runtime plans; single credential for compute + browser. | Treat e2b as a runtime; surface the browser via the runtime API. |
| **Modal + headless Chrome** | Users already on Modal avoid a second account. | Same: probably surfaces through the runtime API, not the browser provider registry. |

## Work, per provider we keep

For each accepted provider:

1. **Adapter.** Implement `XxxProvider implements BrowserEndpointProvider`
   under `cli/lib/src/web/browser/providers/<name>_provider.dart`. Mirror
   the shape of existing ones (`browserbase_provider.dart` is a good
   template).
2. **Config.** Extend `BrowserConfig` with per-provider fields. Update
   `docs/reference/config-yaml.md` — the canonical source the website's
   config-examples generator reads.
3. **Registration.** Register in `BrowserManager.pickProvider`.
4. **Tests.** Cover `isConfigured`, URL/WS building, and one happy-path
   provisioning test. Skip live network calls — mock the HTTP client.
5. **Docs.** Update `website/docs/advanced/browser-automation.md` with a
   row in the backends table and a config snippet.
6. **Status label.** Add the provider to `website/data/feature-status.yaml`.
7. **Credentials.** Document the required env-var name in the
   Configuration page under Credentials.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Decision doc committed: for each candidate, "accept / defer" with
      one reason.
- [ ] #2 At least one standard cloud browser shipped behind
      `<FeatureStatus status="experimental" />` (Cloudflare Browser
      Rendering recommended first — small API surface).
- [ ] #3 At least one unblocking/scraping provider shipped (Bright Data
      is the reference product here).
- [ ] #4 Playwright local provider evaluated. If accepted, shipped as
      `local-playwright`; if deferred, rationale recorded.
- [ ] #5 Backends table on `/docs/advanced/browser-automation` lists every
      shipped provider with honest status labels.
- [ ] #6 `feature-status.yaml` + consistency checker pass.
- [ ] #7 Per-provider credentials documented in the Configuration page.
<!-- AC:END -->



## Notes

- Keep `BrowserEndpointProvider` minimal. If a provider needs a bespoke
  session lifecycle (snapshots, retries, branched sessions), consider
  whether that should be a separate capability rather than pushing it into
  every adapter.
- Coordinate with TASK-26 (runtime boundary). Runtimes that naturally host
  a browser (e2b, Modal, Scrapybara's desktop) should surface the browser
  via the runtime API — not as a parallel browser backend registration.
- Unblocking-class providers (Bright Data, Oxylabs, Zyte) typically charge
  per GB or per session and route through residential IP pools. The
  adapter is thin; the real work is documenting setup and pricing so users
  aren't surprised by their first invoice.
<!-- SECTION:DESCRIPTION:END -->
