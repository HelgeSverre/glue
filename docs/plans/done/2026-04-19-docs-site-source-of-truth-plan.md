# Docs And Website Source Of Truth Plan

Status: proposed
Owner: implementation agent
Date: 2026-04-19

## Goal

Keep getglue.dev, VitePress docs, CLI reference docs, and TUI demos from
drifting apart.

The website redesign plan defines the page structure. This plan defines how
content should be sourced so the site does not claim behavior the CLI no longer
has.

## Current Code Context

Relevant paths:

- `website/`
- `devdocs/`
- `docs/plans/2026-04-19-website-redesign-plan.md`
- `cli/docs/reference/models.yaml`
- `cli/docs/reference/config-yaml.md`
- `cli/docs/reference/session-storage.md`
- `cli/docs/reference/glue-home-layout.md`
- `cli/docs/design/tui-theme-system.md`
- `cli/bin/glue_theme_demo.dart`

Current shape:

- `website/` contains static HTML pages.
- `devdocs/` contains VitePress docs.
- CLI docs contain reference material that is closer to implementation.
- TUI examples live partly in demos and partly in docs.

## Risk

The more examples are copied by hand, the faster they go stale:

- model names drift from the catalog
- install commands drift from packaging
- config snippets drift from parser behavior
- TUI screenshots drift from renderer behavior
- session log examples drift from JSONL schema
- website roadmap implies unfinished features are shipped

## Source Rules

### Models

Canonical source:

- `cli/docs/reference/models.yaml`

Website/docs should derive:

- provider list
- recommended model table
- OpenAI-compatible examples
- local model examples

Do not hardcode separate model tables in website pages.

### Config

Canonical sources:

- `cli/docs/reference/config-yaml.md`
- future `cli/docs/reference/config.schema.yaml` or generated schema
- `cli/docs/reference/models.yaml`

Website snippets may be shorter, but should be copied from tested examples or
generated snippets.

### Session Logs

Canonical source:

- `cli/docs/reference/session-storage.md`
- future session JSONL schema doc

Website should not invent event names.

### TUI

Canonical sources:

- `cli/bin/glue_theme_demo.dart`
- `cli/docs/design/tui-theme-system.md`
- future TUI behavior contract doc

Prefer generated screenshots or scripted renders over hand-built screenshots.

### Install Commands

Canonical source should be one small doc/snippet, for example:

```text
docs/snippets/install.md
```

Every site page should include that snippet rather than repeating commands.

## Suggested Generated Artifacts

Add a lightweight docs generation script later:

```text
tool/generate_site_reference.dart
```

Inputs:

- `cli/docs/reference/models.yaml`
- config reference examples
- TUI demo fixture outputs
- changelog/release metadata

Outputs:

- `devdocs/generated/models.md`
- `devdocs/generated/config-examples.md`
- `devdocs/generated/session-events.md`
- `devdocs/public/tui/*.svg` or terminal render snapshots

Keep generated files obviously marked:

```md
<!-- Generated from cli/docs/reference/models.yaml. Do not edit by hand. -->
```

## Website Content Honesty Rules

Use feature status labels:

- `shipping`
- `experimental`
- `planned`

Examples:

- Docker shell runtime: shipping/experimental depending on stability
- Cloud runtimes: planned
- JSONL sessions: shipping, with schema expansion planned
- model catalog refresh: planned
- web/browser tooling: shipping or experimental by backend

Do not put planned features in the hero as if they are complete.

## VitePress Integration

Recommended site structure remains VitePress-first:

```text
devdocs/
  index.md
  pages/
    why.md
    features.md
    models.md
    runtimes.md
    web.md
    sessions.md
  guide/
    getting-started/
    using-glue/
    advanced/
    contributing/
  generated/
    models.md
    config-examples.md
```

Custom Vue components:

- `TerminalDemo.vue`
- `ModelTable.vue`
- `RuntimeMatrix.vue`
- `FeatureStatus.vue`
- `ConfigSnippet.vue`

These components should receive data from generated JSON or Markdown
frontmatter, not duplicate full tables internally.

## Implementation Plan

1. Keep the website redesign VitePress-first.
2. Move valuable static `website/` content into VitePress pages.
3. Add source-of-truth comments to generated or copied examples.
4. Add a small generation script for model/provider tables first.
5. Add feature status labels to roadmap and feature pages.
6. Generate TUI screenshots/renders only after the TUI behavior contract is
   stable.
7. Archive old static pages after route coverage exists.

## Tests And Checks

Add checks for:

- every model shown on `/models` exists in `models.yaml`
- every provider shown on `/models` exists in `models.yaml`
- every JSONL event example exists in the session schema doc
- generated docs are up to date
- install command snippet appears consistently
- planned features are not marked as shipping

## Acceptance Criteria

- There is one provider/model source of truth.
- Website examples match CLI reference docs.
- Planned runtime/provider features are clearly labelled.
- Static `website/` pages no longer compete with VitePress content.
- A follow-up agent can regenerate model docs without hand-editing tables.

## Open Questions

- Should generated docs be committed, or generated during site build?
- Should TUI renders be SVG, PNG screenshots, or ANSI text blocks?
- Should feature status be stored in one YAML file?
- Should `website/` be deleted after VitePress migration or kept as archive?
