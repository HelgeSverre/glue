---
pageClass: page-marketing
title: Web Tools
description: Glue's web tools — search, fetch with OCR, and browser automation. Practical tooling for scraping, research, and automation.
sidebar: false
aside: false
outline: false
---

# Web Tools

Glue ships three web tools by default: `web_search`, `web_fetch`, and
`web_browser`. The surface is a little wider than in most coding agents
because I use Glue for scraping and automation about as much as for coding —
nothing hype, just more practical capability than you'd typically find.

Everything below works out of the box. Providers with API keys light up
automatically. Browser backends swap with one config line.

## The tools at a glance

| Tool | What it does | Status |
| --- | --- | --- |
| [`web_search`](#search) | Query Brave, Tavily, or Firecrawl. Provider auto-detected from env. | <FeatureStatus status="shipping" /> |
| [`web_fetch`](#fetch) | HTML → cleaned markdown, PDF → text. OCR and Jina fallbacks. | <FeatureStatus status="shipping" /> |
| [`web_browser`](#browser) | Drive a real Chrome over CDP. Six actions, five backends. | <FeatureStatus status="experimental" /> |

## Search

<FeatureStatus status="shipping" />

Three providers, one interface. Glue looks at the environment on startup and
picks the first key it finds. You can pin a provider in config if more than
one is set.

| Provider | Strength | Env var |
| --- | --- | --- |
| Brave | General results, straightforward developer plan. | `BRAVE_API_KEY` |
| Tavily | Agent-focused; returns short summaries with results. | `TAVILY_API_KEY` |
| Firecrawl | Search plus a crawl/scrape API on the same key. | `FIRECRAWL_API_KEY` |

<ConfigSnippet title="~/.glue/config.yaml — pin a search provider">

```yaml
web:
  search:
    provider: brave        # brave | tavily | firecrawl
```

</ConfigSnippet>

## Fetch

<FeatureStatus status="shipping" />

`web_fetch` reads a URL and returns it in a form the model can use — HTML
cleaned to markdown, PDFs as extracted text. It has two fallbacks for the
awkward cases:

- **OCR** for scanned PDFs. If a PDF has no extractable text layer, Glue
  passes the pages to a vision model (Mistral or OpenAI) and returns the
  OCR'd text instead. Useful for government documents, old filings, or
  anything scanned from paper.
- **Jina Reader** for pages that extract poorly with the default cleaner.
  Set `JINA_API_KEY` and Glue routes difficult fetches through Jina.

<ConfigSnippet title="~/.glue/config.yaml — fetch with OCR + Jina">

```yaml
web:
  fetch:
    jina_api_key: ${JINA_API_KEY}       # optional, for hostile pages
  pdf:
    enabled: true
    ocr_provider: mistral               # mistral | openai
    mistral_api_key: ${MISTRAL_API_KEY}
```

</ConfigSnippet>

## Browser

<FeatureStatus status="experimental" />

`web_browser` drives a real Chrome over the DevTools Protocol. The CDP
backend is experimental — it works across all providers but is newer than
the rest of Glue, and rough edges should be expected.

### Actions

Six verbs, all running against a single browser session that persists across
tool calls within the same turn. The agent can navigate, fill a form, submit,
and read the result without reopening the tab.

| Action | Use for |
| --- | --- |
| `navigate` | Open a URL; waits for network idle. |
| `click` | Click any selector in the live DOM. |
| `type` | Fill an input. |
| `screenshot` | Full page or a single element, saved to disk. |
| `extract_text` | Cleaned markdown of the current page (capped at ~50k tokens). |
| `evaluate` | Run arbitrary JavaScript in page context and return the result. |

### Backends

All five implement the same `BrowserEndpointProvider` interface, so swapping
is a one-line config change rather than a code change.

| Backend | Runs on | Best for | Status |
| --- | --- | --- | --- |
| `local` | Your machine (Puppeteer + Chrome) | Iteration. `headed: true` lets you watch it work. | <FeatureStatus status="shipping" /> |
| `docker` | Local `browserless/chrome` container | Keeping the browser off your host. Container dies with the session. | <FeatureStatus status="shipping" /> |
| `browserbase` | Cloud — [browserbase.com](https://browserbase.com) | Hosted sessions with replays. | <FeatureStatus status="experimental" /> |
| `browserless` | Cloud or self-hosted — [browserless.io](https://browserless.io) | Scale and self-hosting. | <FeatureStatus status="experimental" /> |
| `steel` | Cloud — [steel.dev](https://steel.dev) | Agent-focused cloud sessions. | <FeatureStatus status="experimental" /> |

<ConfigSnippet title="~/.glue/config.yaml — switch browser backends">

```yaml
web:
  browser:
    backend: docker        # local | docker | browserbase | browserless | steel
    docker_image: browserless/chrome:latest
    docker_port: 3000
```

</ConfigSnippet>

Cloud backends need an API key. Prefer env vars or
[`~/.glue/credentials.json`](/docs/getting-started/configuration#credentials-json-api-keys)
over committing keys into `config.yaml`.

## Credentials

Every API key resolves in the same order: environment first, then
`~/.glue/credentials.json`, then — if you really insist — `config.yaml`.
Nothing auto-reads project-local config.

| What needs a key | Env var |
| --- | --- |
| Brave search | `BRAVE_API_KEY` |
| Tavily search | `TAVILY_API_KEY` |
| Firecrawl search | `FIRECRAWL_API_KEY` |
| Jina fetch fallback | `JINA_API_KEY` |
| Mistral OCR | `MISTRAL_API_KEY` |
| OpenAI OCR | `OPENAI_API_KEY` |
| Browserbase browser | `BROWSERBASE_API_KEY` + `BROWSERBASE_PROJECT_ID` |
| Browserless browser | `BROWSERLESS_API_KEY` |
| Steel browser | `STEEL_API_KEY` |

## Pairing with runtimes

Web tools compose with Glue's runtime — pair them when the work is risky or
you don't want the traffic on your host.

| Goal | Suggested pairing |
| --- | --- |
| Quick fetch or a search | Host runtime + whatever provider you have. |
| Clicking through an untrusted site | Docker runtime + Docker browser. |
| Reading a scanned filing | Any runtime + fetch with OCR. |
| Scale scraping | <FeatureStatus status="planned" /> Cloud runtime + cloud browser. |

Full matrix of runtime × browser combinations lives on the
[Runtimes page](/runtimes).

<p>
  <a href="/docs/advanced/web-tools">Web tools guide →</a>
  · <a href="/docs/advanced/browser-automation">Browser automation guide →</a>
</p>
