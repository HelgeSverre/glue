# Config Init And Command Surface Plan

Status: proposed
Owner: implementation agent
Date: 2026-04-19

## Goal

Define a coherent plan for:

1. correcting and expanding Glue's `config.yaml` documentation so it matches the implementation,
2. adding a non-interactive CLI command for initializing or resetting config files,
3. documenting command-surface conventions so future command families land in the right place, and
4. identifying adjacent command areas where a `glue <noun> <verb>` pattern makes sense.

This plan is intentionally broader than just `glue config init`. The config work exposed a more general surface-design question: which actions belong in the TUI slash-command layer versus the top-level CLI command layer.

---

## Summary

Recommended direction:

- Rewrite `docs/reference/config-yaml.md` to document the actual v2 config shape.
- Add `glue config init` as the canonical non-interactive way to create a fully annotated `~/.glue/config.yaml` template.
- Support `glue config init --force` for reset/overwrite behavior.
- Keep `/config` inside the TUI, but narrow its role to interactive convenience:
  - open config in `$EDITOR`
  - optionally delegate to the same template writer later if `/config init` remains useful
- Establish a documented convention:
  - **top-level CLI subcommands** for setup, diagnostics, and scriptable filesystem/config workflows
  - **slash commands** for interactive session actions
- Audit nearby command opportunities and document which should or should not adopt the same pattern.

---

## Current Code Context

### Config loading

The authoritative runtime behavior lives in:

- `cli/lib/src/config/glue_config.dart`
- `cli/lib/src/core/environment.dart`
- `cli/lib/src/shell/shell_config.dart`
- `cli/lib/src/shell/docker_config.dart`
- `cli/lib/src/web/web_config.dart`
- `cli/lib/src/web/browser/browser_config.dart`
- `cli/lib/src/config/constants.dart`

Important facts from the current implementation:

- `config.yaml` resolves from `GLUE_HOME` or `~/.glue/config.yaml`
- YAML is loaded with `loadYaml(...)`
- `GlueConfig.load()` manually merges:
  - CLI flags
  - environment variables
  - YAML file
  - defaults and catalog defaults
- config parsing is handwritten field-by-field, not schema-generated
- legacy v1 config is explicitly rejected via `_rejectLegacyConfig(...)`

### Current docs drift

`docs/reference/config-yaml.md` is out of date. It still documents legacy fields such as:

- `provider`
- `model`
- `<provider>.api_key`
- `title_model`
- profile objects shaped as nested maps

But current runtime expects v2 concepts such as:

- `active_model`
- `small_model`
- `profiles` as string refs
- `title_generation_enabled`
- credentials stored separately in `~/.glue/credentials.json` and env vars

### Current command surfaces

#### Top-level CLI

Today `bin/glue.dart` has:

- top-level flags like `--where`, `--model`, `--resume`, `--continue`
- one top-level subcommand family:
  - `glue completions install`
  - `glue completions uninstall`

This means the top-level CLI already supports noun-based command families.

#### TUI slash commands

Current slash commands include:

- `/model`
- `/resume`
- `/provider`
- `/config`
- `/open`
- `/paths`
- etc.

Relevant current detail:

- `/config` already has a subcommand form implemented in `cli/lib/src/app/command_helpers.dart`
- `/config init` currently calls `initLocalConfig(app._cwd)`
- `initLocalConfig(...)` just creates an empty `./config.yaml` in the current working directory

That current `/config init` behavior does **not** match actual Glue config resolution semantics, which point at `~/.glue/config.yaml` via `Environment.configYamlPath`.

This is a usability trap and should be corrected or clearly repurposed.

---

## How `config.yaml` Actually Loads

The loader path should be documented in the plan because it drives both docs and `glue config init` design.

### Path resolution

`Environment.detect()` computes:

- `glueDir = GLUE_HOME ?? $HOME/.glue`
- `configYamlPath = $glueDir/config.yaml`

So the primary user config file is:

- `~/.glue/config.yaml`
- or `$GLUE_HOME/config.yaml`

### Parse flow

`GlueConfig.load()`:

1. reads environment vars,
2. resolves the config path,
3. reads the file if present,
4. parses YAML with `loadYaml`,
5. converts `YamlMap` to `Map<String, dynamic>`,
6. rejects the old legacy v1 shape,
7. applies per-field precedence logic,
8. constructs typed Dart objects.

### Object construction

The YAML is not deserialized directly into one DTO. Instead it is converted manually into:

- `GlueConfig`
- `ShellConfig`
- `DockerConfig`
- `WebConfig`
  - `WebFetchConfig`
  - `WebSearchConfig`
  - `PdfConfig`
  - `BrowserConfig`
- `ObservabilityConfig`
- `ApprovalMode`

### Real precedence rules

The docs should explain precedence per field family, not just as one simplified global statement.

Examples:

- active model:
  1. CLI `--model`
  2. `GLUE_MODEL`
  3. YAML `active_model`
  4. catalog default

- title generation toggle:
  1. `GLUE_TITLE_GENERATION_ENABLED`
  2. YAML `title_generation_enabled`
  3. default `true`

- shell executable:
  1. `GLUE_SHELL`
  2. YAML `shell.executable`
  3. `SHELL`
  4. fallback `sh`

This argues for a more structured and annotated config reference.

---

## Actual Config Surface To Document

The plan should capture the current known YAML keys so the follow-up doc rewrite and template generation have a checklist.

### Top-level keys currently parsed

- `active_model`
- `small_model`
- `profiles`
- `catalog`
- `bash`
- `shell`
- `docker`
- `web`
- `debug`
- `approval_mode`
- `title_generation_enabled`
- `skills`

### Nested keys currently parsed

#### `catalog`

- `refresh`
- `remote_url`

#### `bash`

- `max_lines`

#### `shell`

- `executable`
- `mode`

#### `docker`

- `enabled`
- `image`
- `shell`
- `fallback_to_host`
- `mounts`

#### `web.fetch`

- `jina_api_key`
- `allow_jina_fallback`
- `timeout_seconds`
- `max_bytes`
- `max_tokens`

#### `web.search`

- `provider`
- `brave_api_key`
- `tavily_api_key`
- `firecrawl_api_key`
- `firecrawl_base_url`
- `timeout_seconds`
- `max_results`

#### `web.pdf`

- `mistral_api_key`
- `openai_api_key`
- `ocr_provider`
- `max_bytes`
- `timeout_seconds`
- `enable_ocr_fallback`

#### `web.browser`

- `backend`
- `headed`
- `docker.image`
- `docker.port`
- `steel.api_key`
- `browserbase.api_key`
- `browserbase.project_id`
- `browserless.base_url`
- `browserless.api_key`
- `anchor.api_key`
- compatibility fallback: `anchor_api_key`
- `hyperbrowser.api_key`
- compatibility fallback: `hyperbrowser_api_key`

#### `skills`

- `paths`

### Environment variables currently relevant

At minimum, the rewritten docs and template should account for:

- `GLUE_HOME`
- `GLUE_MODEL`
- `GLUE_DEBUG`
- `GLUE_APPROVAL_MODE`
- `GLUE_TITLE_GENERATION_ENABLED`
- `GLUE_SKILLS_PATHS`
- `GLUE_CATALOG_CACHE`
- `GLUE_SHELL`
- `GLUE_SHELL_MODE`
- `SHELL`
- `GLUE_DOCKER_ENABLED`
- `GLUE_DOCKER_IMAGE`
- `GLUE_DOCKER_SHELL`
- `GLUE_DOCKER_MOUNTS`
- `JINA_API_KEY`
- `BRAVE_API_KEY`
- `TAVILY_API_KEY`
- `FIRECRAWL_API_KEY`
- `GLUE_SEARCH_PROVIDER`
- `GLUE_OCR_PROVIDER`
- `GLUE_BROWSER_BACKEND`
- `STEEL_API_KEY`
- `BROWSERBASE_API_KEY`
- `BROWSERBASE_PROJECT_ID`
- `BROWSERLESS_API_KEY`
- `ANCHOR_API_KEY`
- `HYPERBROWSER_API_KEY`
- provider credential env vars handled by provider auth/credential resolution, such as `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `MISTRAL_API_KEY`

### Known invalid/stale doc concepts to remove

The rewrite should explicitly eliminate or migrate references to:

- `provider`
- `model`
- `title_model`
- top-level provider API keys in `config.yaml`
- profile maps shaped as `{ provider, model }`
- flat browser fields that do not match the runtime nesting

---

## Problem Statement: `/config init` Is Misleading Today

Current slash behavior:

- `/config` opens `~/.glue/config.yaml` in `$EDITOR`
- `/config init` creates an empty `./config.yaml` in the cwd

This is inconsistent because:

- one action targets the real Glue home config
- the other creates a local file outside the runtime resolution path
- the created file is empty and undocumented

Unless there is a deliberate future design for project-local config overrides, this command should not remain as-is.

### Recommendation

Replace the current meaning of config initialization with a canonical non-interactive CLI command:

```bash
glue config init
glue config init --force
```

And then choose one of these paths for slash `/config init`:

1. **Remove `/config init` entirely** and keep `/config` as editor-open only.
2. **Make `/config init` call the same implementation** as `glue config init`.
3. **Repurpose `/config init local`** only if a future local-project config layer is formally designed.

Recommendation: **option 2 or 1**, with a bias toward **2** if we want parity and convenience.

---

## Proposed CLI Surface

### Primary command

```bash
glue config init
```

Behavior:

- resolve the real config destination via `Environment.detect().configYamlPath`
- create parent directories if needed
- write a fully annotated config template
- refuse to overwrite existing config unless `--force` is passed

### Reset behavior

```bash
glue config init --force
```

Behavior:

- overwrite the existing file with a fresh annotated template
- clearly state the target path in output

### Future adjacent commands

The same namespace can plausibly grow to:

```bash
glue config path
glue config show
glue config validate
```

Recommended status:

- `config init` — implement now
- `config path` — small, useful, reasonable follow-up
- `config show` — useful but lower priority
- `config validate` — likely redundant once `glue doctor` exists, unless it becomes a focused fast-path validator

---

## Template Requirements

The generated config should behave like a Laravel-style documented config file.

### Requirements

- list all currently supported YAML keys
- use the **actual runtime field names and nesting**
- include comments describing valid values, defaults, and env overrides where practical
- keep optional entries commented out where appropriate
- explain the split between:
  - `config.yaml`
  - `credentials.json`
  - env vars
- avoid documenting unsupported keys just because they were present historically

### Important caveat

This template is a **starter artifact**, not a round-trippable representation. Comments will be lost if any future code rewrites the file programmatically. That is acceptable; the point is discoverability and first-run guidance.

### Preferred implementation

Add a shared template builder, e.g.:

- `cli/lib/src/config/config_template.dart`

With a function such as:

```dart
String buildConfigTemplate()
```

This same template can then be used by:

- `glue config init`
- `/config init` if retained
- docs generation or copy into `docs/reference/config-yaml.md`

---

## Command Surface Convention

This plan recommends a reusable rule:

### Use top-level CLI subcommands for

- setup and initialization
- diagnostics
- filesystem/reporting workflows
- machine/script-friendly actions
- tasks the user may want before launching the TUI

Examples:

- `glue completions install`
- `glue config init`
- `glue doctor`

### Use slash commands for

- in-session navigation
- model/session/provider interaction while already inside Glue
- actions whose primary UX is interactive and panel-driven

Examples:

- `/model`
- `/resume`
- `/history`
- `/provider`
- `/config`

### Naming preference

Prefer **noun namespaces** for extensible CLI areas:

- `glue config init`
- `glue config show`
- `glue config path`

Avoid growing unrelated top-level verbs when the actions are clearly part of one domain.

---

## Adjacent Command Opportunities

This section audits nearby commands to decide where the same pattern does or does not make sense.

### 1. `glue config ...`

Strong fit.

Potential family:

- `glue config init`
- `glue config path`
- `glue config show`

Rationale:

- config is a durable resource
- these actions are useful outside the TUI
- these actions are easy to script and document
- this aligns with the existing `completions` family

### 2. `glue doctor`

Already has its own plan in `docs/plans/2026-04-20-glue-doctor-plan.md`.

Assessment:

- **keep as top-level command**, not a slash command
- likely best as a direct top-level noun/verbless command because it is a well-known diagnostic idiom
- no need to force `glue system doctor` or similar namespace unless more system commands appear later

### 3. `glue paths` or `glue where`

Current behavior is a top-level flag `--where` and slash `/paths`.

Assessment:

- there is a case for eventually promoting this to a first-class top-level command such as `glue paths`
- but this is not urgent
- if changed later, document migration from `--where`

Recommendation:

- do **not** expand scope now
- mention as future cleanup only

### 4. `glue open ...`

Current behavior exists only as slash `/open`.

Assessment:

- possible future CLI candidate, but lower priority
- opening file managers is interactive and OS-specific, so slash/TUI convenience is fine for now
- scriptability value is lower than for config/doctor

Recommendation:

- keep slash-only for now

### 5. `glue provider ...`

Current behavior is slash `/provider` only.

Assessment:

- there is eventual value in a non-interactive provider namespace, especially for CI/bootstrap setups
- but the current provider flows are panel- and credential-entry-oriented
- this becomes more compelling only once there is a robust headless credential story

Possible future family:

- `glue provider list`
- `glue provider add <id>`
- `glue provider remove <id>`
- `glue provider test <id>`

Recommendation:

- document as future opportunity, not immediate scope

### 6. `glue session ...`

Current interactive surface already has `/session`, `/resume`, `/history`.

Assessment:

- top-level session management commands may eventually make sense
- but current session flows are still evolving and already covered by a dedicated slash-command conventions plan
- avoid starting a second command family until the session semantics settle

Recommendation:

- explicitly out of scope for this plan

---

## Proposed Implementation Phases

### Phase 1 — research capture and convention docs

1. Record this plan in `docs/plans/`.
2. Add command-surface guidance to `CLAUDE.md`.
3. Cross-reference related plans:
   - slash command conventions
   - doctor plan
   - docs source-of-truth plan

### Phase 2 — config template and docs rewrite

1. Add a shared config template builder.
2. Rewrite `docs/reference/config-yaml.md` around the actual v2 config format.
3. Ensure the docs explain:
   - config path resolution
   - YAML-to-Dart conversion path
   - env precedence
   - credentials split
4. If feasible, include a generated-source note or shared-snippet provenance to reduce drift.

### Phase 3 — CLI command implementation

1. Add a `config` top-level subcommand family in `cli/bin/glue.dart`.
2. Implement:
   - `glue config init`
   - `glue config init --force`
3. Return clear exit codes and user-facing messages.
4. Add tests around:
   - missing file create
   - existing file refusal
   - `--force` overwrite
   - `GLUE_HOME` target resolution

### Phase 4 — slash `/config` cleanup

Choose and implement one:

- remove `/config init`, or
- make `/config init` delegate to the same shared writer as `glue config init`

In either case:

- fix the slash command description so it reflects reality
- remove the current `cwd`-local empty-file behavior unless a separate local-config design is approved

### Phase 5 — optional follow-ups

Evaluate small additions if momentum remains:

- `glue config path`
- `glue config show`
- promote `--where` into `glue paths`
- future provider CLI family

---

## Testing Strategy

### Docs-level checks

- ensure `docs/reference/config-yaml.md` no longer mentions rejected legacy keys without a migration warning
- ensure examples use current field names (`active_model`, `small_model`, etc.)

### Unit tests

For config template generation:

- template contains all expected section headings and keys
- template uses actual supported key names
- template does not include stale unsupported keys

### CLI tests

For `glue config init`:

- creates config at `Environment.configYamlPath`
- respects `GLUE_HOME`
- refuses overwrite by default
- overwrites with `--force`
- output mentions written path

### Slash tests

If `/config init` is retained:

- it writes to the same path as `glue config init`
- it no longer writes `./config.yaml`

---

## Acceptance Criteria

- A new engineer can discover the real supported config surface from `docs/reference/config-yaml.md` without reading loader code.
- The config docs describe the actual runtime file shape and precedence rules.
- `glue config init` exists and writes a comprehensive annotated config template.
- Reset/overwrite behavior exists via `--force`.
- `CLAUDE.md` documents the command-surface convention for future features.
- The current misleading `/config init` local-file behavior is removed or replaced.
- The plan documents which adjacent command families are immediate fits and which are deferred.

---

## Open Questions

1. Should the docs page be generated directly from the template builder, or just share content manually at first?
   - Recommendation: share a template builder first, generation later.

2. Should `/config init` remain available inside the TUI?
   - Recommendation: yes only if it delegates to the same real config initializer.

3. Should `glue config validate` exist separately from `glue doctor`?
   - Recommendation: defer until after doctor lands.

4. Should a future project-local config layer exist?
   - Recommendation: do not imply one until its resolution semantics are designed and implemented.

---

## Related Plans

- `docs/plans/2026-04-20-slash-command-conventions.md`
- `docs/plans/2026-04-20-glue-doctor-plan.md`
- `docs/plans/2026-04-19-docs-site-source-of-truth-plan.md`

---

## Immediate Follow-Up Recommendation

The next implementation PR should likely do these together:

1. add the shared config template,
2. rewrite `docs/reference/config-yaml.md`,
3. add `glue config init --force`, and
4. retire or repoint the current `/config init` behavior.

That keeps docs, runtime, and interactive UX aligned in one pass.
