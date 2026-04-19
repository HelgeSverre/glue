---
pageClass: page-marketing
title: Web Tools
description: Fetch, extract, search, and browser automation — practical web tooling that pairs with Docker or future cloud runtimes when the work is risky.
sidebar: false
aside: false
outline: false
---

# Web Tools

Glue's web tools are practical, not flashy. Scrape a page. Pull structured
data. Inspect a site. Automate a browser session. Pair any of it with a Docker
runtime when you don't want the traffic or the artifacts on your host.

## What's in the box

### Fetch

<FeatureStatus status="shipping" /> Read a page or a file over HTTP, optionally
through a Jina Reader key for cleaner extraction.

**When you use this:** pulling a reference doc into context, checking a
changelog, reading a public-issue thread.

### Search

<FeatureStatus status="shipping" /> Query a search provider and get back
structured results. Providers: Brave, Tavily, Firecrawl.

**When you use this:** looking up current documentation, tracking down an
error message, broad research before a task.

### PDF extraction

<FeatureStatus status="shipping" /> OCR-backed text extraction. Backends:
Mistral, OpenAI.

**When you use this:** reading whitepapers, specs, or attachments in a session.

### Browser automation

<FeatureStatus status="experimental" /> Drive a headless browser through
Chrome DevTools Protocol. Backends: local Chrome, Docker (`browserless/chrome`),
Steel, Browserbase, Browserless.

**When you use this:** clicking through auth-protected flows, interacting
with JS-rendered pages, taking screenshots, or extracting data that needs a
real browser.

## Configuration

<ConfigSnippet title="~/.glue/config.yaml — web tool backends">

```yaml
web:
  fetch:
    jina_api_key: your-key
  search:
    provider: brave          # brave | tavily | firecrawl
    brave_api_key: your-key
  pdf:
    enabled: true
    ocr_provider: mistral    # mistral | openai
    mistral_api_key: your-key
  browser:
    backend: docker          # local | docker | steel | browserbase | browserless
    docker_image: browserless/chrome:latest
    docker_port: 3000
```

</ConfigSnippet>

## Pairing with runtimes

| Goal | Suggested pairing |
| --- | --- |
| Casual fetch/search | Host + any backend |
| Untrusted site inspection | Docker runtime + local browser backend |
| High-volume scraping | <FeatureStatus status="planned" /> Cloud runtime + remote browser backend |
| Suspicious artifacts | Docker runtime, fetch only inside the sandbox |

## What we don't do

- No stealth, anti-bot bypass, or CAPTCHA defeat.
- No credential harvesting helpers.
- No abusive automation flows.

The goal is practical research and automation, not traffic you can't explain.

<p><a href="/docs/advanced/web-tools">Web tools guide →</a> · <a href="/docs/advanced/browser-automation">Browser automation guide →</a></p>
