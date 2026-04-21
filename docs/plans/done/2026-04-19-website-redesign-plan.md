# getglue.dev Website Redesign Plan

Status: proposed
Owner: implementation agent
Date: 2026-04-19

## Goal

Make the website explain Glue quickly to technical users:

- what Glue is
- why it exists
- how to install it
- how it differs from IDE assistants and heavier agent stacks
- how models, providers, runtimes, web tools, Docker, and sessions fit together
- where the docs live

The current repo has `website/` static pages and `devdocs/` VitePress docs. The
recommended first step is to consolidate around VitePress with custom Vue pages
for the marketing surface. Move to Astro only if the site starts needing a much
larger visual system, content collections, landing-page variants, or richer
non-doc publishing workflows.

## Recommended Architecture

Use VitePress for both the homepage and docs:

```text
getglue.dev/
  /                  custom VitePress homepage
  /why               custom page
  /features          custom page
  /models            custom page
  /runtimes          custom page
  /web               custom page
  /sessions          custom page
  /docs/             normal VitePress docs
  /changelog         generated or manually maintained
  /roadmap           public roadmap
```

Why:

- one build system
- one theme, nav, search, deploy path, and markdown pipeline
- docs can link into product pages without crossing domains
- custom Vue components are enough for terminal demos and comparison tables
- avoids adding Astro while the product and messaging are still moving

Keep `docs.getglue.dev` as a later option if the marketing site outgrows
VitePress. If that happens, use Astro for `getglue.dev` and keep VitePress at
`docs.getglue.dev`.

## Sitemap

### Public Pages

```text
/                 Home
/why              Why Glue
/features         Feature overview
/models           Models and providers
/runtimes         Local, Docker, and cloud runtimes
/web              Web browsing, scraping, and research
/sessions         Sessions, logs, and replay
/roadmap          What is near, next, and later
/changelog        Release notes
/brand            Logos, colors, screenshots, naming
```

### Docs

```text
/docs/getting-started/installation
/docs/getting-started/quick-start
/docs/getting-started/configuration
/docs/using-glue/interactive-mode
/docs/using-glue/models-and-providers
/docs/using-glue/tools
/docs/using-glue/sessions
/docs/using-glue/file-references
/docs/using-glue/worktrees
/docs/using-glue/docker-sandbox
/docs/advanced/runtimes
/docs/advanced/browser-automation
/docs/advanced/web-tools
/docs/advanced/mcp-integration
/docs/advanced/skills
/docs/advanced/subagents
/docs/advanced/troubleshooting
/docs/contributing/development-setup
/docs/contributing/architecture
/docs/contributing/testing
```

## Home Page Outline

### Hero

Purpose: explain the product in one screen and get users to the first command.

Content:

- headline: "A small terminal agent for real coding work."
- subhead: "Glue edits files, runs tools, keeps resumable sessions, and can run
  work locally, in Docker, or later on remote runtimes."
- primary action: install command
- secondary action: docs link
- full-width terminal demo, not a split column layout

Terminal demo should show:

- user prompt
- assistant response
- tool call group
- file edit summary
- command output
- concise final answer

### Core Loop

Show the actual workflow:

```text
Ask -> inspect -> edit -> run -> verify -> summarize
```

Each step should be concrete and terse. Avoid generic "AI productivity"
language.

### Run Work Where It Belongs

Explain execution targets:

- current machine for normal coding
- Docker sandbox for risky commands and dependency mess
- future cloud runtimes for isolated scraping, malware/static analysis, and
  bursty agent work

Mention likely future targets without overpromising:

- E2B
- Modal
- Daytona
- custom SSH or container workers

### Bring Your Models

Explain the model/provider philosophy:

- curated default model list
- OpenAI, Anthropic, Gemini, Mistral, Groq, Ollama, OpenRouter
- OpenAI-compatible endpoints use `adapter: openai`
- no noisy startup fetch of every legacy provider model
- credentials stay out of project config

Link to `/docs/using-glue/models-and-providers`.

### Web And Research

Position web features as practical, not flashy:

- scrape pages
- extract data
- inspect sites
- run browser automation
- keep risky or noisy browsing off the host machine when paired with Docker or
  remote runtimes

### Sessions

Explain:

- JSONL session logs
- resumable conversations
- known `GLUE_HOME` layout
- simpler observability through append-only logs instead of OpenTelemetry
- replay/debugging as a product feature later

### Final CTA

Keep it direct:

```sh
uv tool install getglue
glue
```

Use the real install command once packaging is settled.

## Page Outlines

### `/why`

Tell the product story:

- terminal-native because coding work already happens in terminals
- small surface area beats a giant mode system
- full-screen TUI is acceptable because Glue already owns the session while it
  works
- Docker and future cloud runtimes make risky work less invasive
- curated provider config avoids model picker noise
- JSONL sessions beat mandatory telemetry for local-first debugging

### `/features`

Feature groups:

- terminal agent loop
- file editing and command execution
- model/provider selection
- sessions and replay
- Docker sandbox
- web browsing and extraction
- subagents and delegated work
- skills/MCP as advanced extension points

Each feature should include one "when you use this" example.

### `/models`

Explain the configuration model:

- selected model is `provider/model`
- providers declare an `adapter`
- `adapter: openai` handles OpenAI-compatible APIs
- credentials use env vars or `~/.glue/credentials.json`
- bundled catalog can be updated later from GitHub or a backend

Include a compact YAML example and link to the full reference catalog.

### `/runtimes`

Explain the runtime ladder:

```text
host -> Docker -> cloud container/runtime
```

Keep the current Docker sandbox as the concrete shipping thing. Present cloud
runtimes as planned extension points, not finished capabilities.

### `/web`

Target use cases:

- research
- scraping
- data extraction
- browser automation
- static site inspection
- suspicious artifacts and malware-adjacent analysis in isolated environments

Avoid promising stealth, bypassing, or abusive automation.

### `/sessions`

Explain:

- where sessions live
- how resume works
- why JSONL is the base format
- how tool calls, outputs, errors, and agent messages appear in logs
- how this can power replay UI later

### `/roadmap`

Suggested sections:

- Now: simplify config, remove plan mode, improve TUI reference behavior
- Next: model catalog refresh, Docker runtime polish, web extraction flows
- Later: cloud runtimes, replay UI, provider marketplace/catalog

Do not make dates unless the release plan is real.

## Content Tone

Use direct technical copy:

- say what Glue does
- show commands and config
- show the TUI
- avoid "10x", "autonomous developer", "magic", or generic AI assistant claims
- prefer examples over claims
- admit what is local, Docker, or future cloud runtime work

## Visual Direction

Keep the visual design aligned with the TUI:

- minimal color
- semantic colors
- compact symbols
- readable terminal blocks
- no decorative gradients as the main identity
- use real screenshots or scripted terminal renders where possible

The homepage hero should use a full-width row layout: text, commands, and the
terminal demo stacked vertically so the terminal gets width. Avoid putting hero
copy and terminal demo in side-by-side columns.

## Implementation Order

1. Pick VitePress as the single site shell for the first redesign.
2. Move the existing static `website/` content worth keeping into VitePress
   pages/components.
3. Keep the current `devdocs/guide/*` pages, but reorganize sidebar labels
   around getting started, using Glue, advanced, and contributing.
4. Add custom Vue components for terminal demos and model/provider tables.
5. Add `/models` and `/runtimes` before broader polish, because these clarify
   product strategy.
6. Add screenshots or generated TUI renders from the reference TUI work.
7. Archive or delete the old static `website/` pages once routes are covered.

## VitePress Versus Astro

### Option A: VitePress Only

Recommended now.

Pros:

- fastest migration
- lowest operational load
- docs and marketing share components
- good enough for a technical CLI product

Cons:

- less flexible than Astro for complex marketing pages
- content modeling is simpler

### Option B: Astro Marketing, VitePress Docs

Use later if the homepage needs richer layouts, blog/content collections, or
more custom visual work.

Pros:

- strong marketing-site ergonomics
- VitePress docs can stay focused

Cons:

- two builds
- duplicated theme/nav/search decisions
- more deployment and routing work

### Option C: Astro With Starlight

Only consider if starting over.

Pros:

- one Astro system for site and docs
- strong docs foundation

Cons:

- migrates away from the existing VitePress setup
- more churn for little immediate product value

## Success Criteria

- A new user can explain Glue after reading the homepage for 30 seconds.
- Install and first-run commands are visible without digging.
- Model/provider configuration is understandable from `/models`.
- Docker and future cloud runtimes are described without implying unfinished
  features are shipped.
- Docs are one click from every product page.
- The site no longer has two competing content systems for the same material.
