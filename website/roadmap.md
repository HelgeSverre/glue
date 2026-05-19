---
pageClass: page-marketing
title: Roadmap
description: What's near, next, and later for Glue. Dates only when a release is real.
sidebar: false
aside: false
outline: false
---

# Roadmap

Everything below is dated by priority, not calendar. If a feature has a date,
that's because the release plan is real. Everything else moves when it's ready.

Legend: <FeatureStatus status="shipping" />
<FeatureStatus status="experimental" />
<FeatureStatus status="planned" />

## Now

Work we're actively simplifying or tightening.

- **Model catalog as a first-class file.** `docs/reference/models.yaml`
  is the single source the CLI and website both read.
  <FeatureStatus status="shipping" />
- **TUI behavior contract.** Pin down scrollback, resize, tool-state
  rendering, and ASCII fallback in a single document so the behavior
  doesn't drift between releases. <FeatureStatus status="planned" />
- **Session JSONL event schema.** Typed events covering tool state
  transitions, file edits, runtime events, and errors.
  <FeatureStatus status="planned" />

## Next

The shape is clear; the work isn't in main yet.

- **Provider adapter contract.** `ProviderAdapter` + `ProviderConfig` +
  `ModelConfig` + `CredentialStore`. Custom providers via
  `adapter: openai` + `compatibility: <profile>`. <FeatureStatus status="planned" />
- **Cloud runtime polish.** Cloud-provided browser CDP, cloud-side
  artifact retrieval, end-of-session diff auto-apply, in-session
  `/runtime switch <name>`, and runtime event persistence to
  `conversation.jsonl`. Daytona / Sprites / Modal already ship — this
  is the followup. <FeatureStatus status="planned" />
- **Docker sandbox polish.** Mount ergonomics, background job handling,
  state preservation across sessions. <FeatureStatus status="experimental" />
- **Web extraction flows.** First-class pipelines for page → structured
  data, built on top of the existing web tools. <FeatureStatus status="experimental" />

## Later

Directions we want to head once the foundations land.

- **More cloud runtimes.** E2B, hopx, Northflank, custom SSH or container
  workers — same `RuntimeFactory.register` adapter pattern proven by
  Daytona, Sprites, and Modal. <FeatureStatus status="planned" />
- **Replay UI.** A dedicated surface that reads `conversation.jsonl`
  and renders it step-by-step with diffs, tool-call collapse, and
  time scrubbing. <FeatureStatus status="planned" />
- **Provider marketplace / catalog refresh.** Optional remote catalog
  fetch, user-submitted providers, bundled-vs-remote merge semantics.
  <FeatureStatus status="planned" />

## Removed

These were in the tree and are coming out — don't plan around them.

- **Interaction modes.** `code` / `architect` / `ask` selector.
- **Plan-mode UI.** The separate `/plans` surface and `PlanStore`.
- **OTEL / Langfuse observability.** JSONL sessions are the single
  durable log.

<p><a href="/changelog">Changelog →</a></p>
