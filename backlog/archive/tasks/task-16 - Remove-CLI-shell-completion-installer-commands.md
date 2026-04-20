---
id: TASK-16
title: Remove CLI shell-completion installer commands
status: To Do
assignee: []
created_date: "2026-04-19 00:34"
labels:
  - simplification-2026-04
  - removal
  - cli
dependencies: []
references:
  - cli/bin/glue.dart
  - cli/pubspec.yaml
documentation:
  - cli/docs/plans/2026-04-19-simplification-removal-plan.md
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->

Remove the `glue completions` CLI command group (install/uninstall shell completion scripts to `~/.bashrc`, `~/.zshrc`, `~/.config/fish`, etc.). ~320 LOC of installer plumbing is large relative to its value.

**KEEP (unrelated, valuable):**

- `cli/lib/src/shell/shell_completer.dart` — in-app bash mode tab completion
- `cli/lib/src/ui/shell_autocomplete.dart` — in-app overlay for bash mode

**Files to modify:**

- `cli/bin/glue.dart` lines ~142–310+ — delete `CompletionsCommand`, `CompletionsInstallCommand`, `CompletionsUninstallCommand`, + helpers (`_installFishCompletion`, `_installPowerShellCompletion`, etc.)
- `cli/pubspec.yaml` — remove `cli_completion` dep if only used here
- `cli/CHANGELOG.md` — migration note: users with stale scripts in `~/.bashrc` should remove them manually
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->

- [ ] #1 `glue completions --help` returns an unknown-command error
- [ ] #2 `ShellCompleter` and `ShellAutocomplete` tests still green
- [ ] #3 `cli_completion` removed from `pubspec.yaml` if only used here
- [ ] #4 CHANGELOG entry explaining removal
- [ ] #5 README updated
- [ ] #6 `dart analyze --fatal-infos` clean
<!-- AC:END -->
