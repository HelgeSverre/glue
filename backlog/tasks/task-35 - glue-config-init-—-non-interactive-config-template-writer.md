---
id: TASK-35
title: glue config init — non-interactive config template writer
status: Done
assignee: []
created_date: '2026-04-20 00:08'
updated_date: '2026-04-20 02:38'
labels:
  - cli
  - config
  - diagnostics
milestone: m-0
dependencies: []
references:
  - cli/bin/glue.dart
  - cli/lib/src/commands/config_command.dart
  - cli/lib/src/config/glue_config.dart
  - docs/reference/config-yaml.md
documentation:
  - docs/plans/2026-04-19-config-init-and-command-surface-plan.md
priority: medium
ordinal: 36000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a top-level `glue config init` subcommand that writes a fully annotated `~/.glue/config.yaml` template. Companion to `glue doctor` (TASK-31) and consistent with the CLI Command Surface Conventions added to `CLAUDE.md`.

**Per the plan (`docs/plans/2026-04-19-config-init-and-command-surface-plan.md`):**
- Rewrite `docs/reference/config-yaml.md` to document the actual v2 config shape (current docs are stale).
- Add `glue config init` as the canonical non-interactive way to seed `~/.glue/config.yaml`.
- Support `glue config init --force` for overwrite/reset.
- Keep `/config` inside the TUI but narrow to interactive convenience (open in `$EDITOR`); optionally delegate to the same template writer.
- Audit nearby command opportunities for the `glue <noun> <verb>` pattern.

**Notes:**
- A stub `cli/lib/src/commands/config_command.dart` already exists with a 12-line `initLocalConfig()` helper. The full subcommand surface (proper `Command<int>` registration on `GlueCommandRunner`, `--force`, annotated template body) is not yet wired.
- The "command-surface conventions" half of the plan has already been distilled into `CLAUDE.md` and into TASK-31/TASK-33 implementation notes.

**Out of scope:**
- Interactive guided onboarding wizard (separate concern).
- Migration from legacy v1 config (already handled by `GlueConfig.load()` rejection).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `glue config init` registered as a top-level subcommand under the `config` noun namespace.
- [x] #2 Writes a fully annotated `~/.glue/config.yaml` template with every documented section commented out and explained.
- [x] #3 `--force` overwrites an existing file; without it, the command refuses and prints the existing path.
- [x] #4 `docs/reference/config-yaml.md` rewritten to match the actual v2 schema produced by the template writer (one source of truth).
- [x] #5 `/config` slash command remains and is narrowed to: open the file in `$EDITOR`. Optionally delegates to the same template writer when no file exists.
- [x] #6 Tests cover: clean creation, `--force` overwrite, refusal without `--force`, template parses cleanly via `GlueConfig.load`.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in `cli/lib/src/commands/config_command.dart` and
`cli/lib/src/config/config_template.dart`, with CLI wiring in
`cli/bin/glue.dart`. `/config init` now writes the resolved
`Environment.configYamlPath`, and `docs/reference/config-yaml.md` documents the
v2 shape plus compatibility fallbacks.
<!-- SECTION:NOTES:END -->
