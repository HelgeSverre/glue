---
id: TASK-31
title: glue doctor — non-interactive install/config diagnostic
status: To Do
assignee: []
created_date: '2026-04-20 00:00'
updated_date: '2026-04-20 00:05'
labels:
  - cli
  - diagnostics
  - config
milestone: m-0
dependencies: []
references:
  - cli/bin/glue.dart
  - cli/lib/src/core/environment.dart
  - cli/lib/src/core/where_report.dart
  - cli/lib/src/config/glue_config.dart
  - cli/lib/src/catalog/catalog_parser.dart
  - cli/lib/src/catalog/catalog_loader.dart
documentation:
  - docs/plans/2026-04-20-glue-doctor-plan.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a non-interactive `glue doctor` top-level subcommand that inspects the user's Glue installation and reports issues. Read-only / diagnosis-only in v1; no mutation, no repair.

**What it should report:**
- Resolved `GLUE_HOME` and core paths (mirror `--where`)
- Presence/absence of expected files and directories
- Parse/shape errors in `config.yaml`, `preferences.json`, `credentials.json`, optional catalog override (`models.yaml`) and cached catalogs
- Config validation issues — e.g. missing required provider credentials for the selected active model
- Malformed session files (`meta.json`, `conversation.jsonl`) and other session-dir inconsistencies
- Filesystem nits like orphaned `.tmp` files

**Implementation shape (per plan):**
- New top-level `Command<int>` registered on `GlueCommandRunner` in `bin/glue.dart` (sibling of `completions`), not a TUI slash command.
- Reuse `Environment` for paths, `WhereReport` for path enumeration, `GlueConfig.load()` + `GlueConfig.validate()` for config health.
- `_loadOptionalYaml()` swallows catalog parse errors today — `doctor` must use stricter parsing for `models.yaml` + cached catalogs to surface those suppressed errors.
- Exit code: `0` clean, non-zero when any check fails (TBD: warning vs. error tiers).
- Output: human-readable by default; consider `--json` for scripts (mirror `glue -p --json`).

**Out of scope (v1):**
- Repair flags (`doctor --fix`)
- Network calls to providers (credential validation stays offline)
- Provider catalog refresh (that lives under TASK-22.7 / `/models refresh`)

See `docs/plans/2026-04-20-glue-doctor-plan.md` for full plan.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `glue doctor` exits 0 on a healthy default install and prints a clean per-check report.
- [ ] #2 Reports parse errors in `config.yaml`, `preferences.json`, `credentials.json`, `models.yaml`, and cached catalog files (does not silently swallow them).
- [ ] #3 Reports missing required credentials for the selected active model.
- [ ] #4 Reports malformed session files (`meta.json`, `conversation.jsonl`) and surfaces orphaned `.tmp` files.
- [ ] #5 Returns a non-zero exit code when any check fails; tier (warning vs error) is documented in plan.
- [ ] #6 Read-only: command never mutates user state in v1.
- [ ] #7 Tests cover: clean install, broken config, missing credential, malformed session.
- [ ] #8 `glue doctor --help` documents the command and is wired into `GlueCommandRunner`.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Conforms to the **CLI Command Surface Conventions** added to `CLAUDE.md` on 2026-04-20: diagnostic / non-interactive surface → top-level CLI subcommand under a noun namespace (`glue doctor`), not a slash command. Aligns with the sibling `glue completions install` precedent and the proposed `glue config init` namespace.
<!-- SECTION:NOTES:END -->
