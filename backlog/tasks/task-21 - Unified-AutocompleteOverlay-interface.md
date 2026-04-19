---
id: TASK-21
title: Unified AutocompleteOverlay interface
status: To Do
assignee: []
created_date: '2026-04-19 00:34'
labels:
  - simplification-2026-04
  - refactor
  - ui
dependencies: []
references:
  - cli/lib/src/ui/slash_autocomplete.dart
  - cli/lib/src/ui/shell_autocomplete.dart
  - cli/lib/src/ui/at_file_hint.dart
  - cli/lib/src/app/terminal_event_router.dart
documentation:
  - cli/docs/plans/2026-04-19-simplification-removal-plan.md
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Three near-identical autocomplete implementations share state shape but no base class (~595 LOC total).

**Files:**
- `cli/lib/src/ui/slash_autocomplete.dart` (~147 LOC)
- `cli/lib/src/ui/shell_autocomplete.dart` (~144 LOC)
- `cli/lib/src/ui/at_file_hint.dart` (~304 LOC)
- `cli/lib/src/app/terminal_event_router.dart` — dispatch currently via `if (slash.active) ... else if (shell.active) ...`

**Duplicated state across all three:** `active`, `selected`, `matchCount`, `overlayHeight`, `maxVisible`, `dismiss()`, `selectNext/Prev`, accept logic.

**Proposed interface (in new file `cli/lib/src/ui/autocomplete_overlay.dart`):**
```dart
abstract class AutocompleteOverlay {
  bool get active;
  int get selected;
  List<String> get displayItems;
  int get overlayHeight;
  Future<void> update(String bufferContext);
  void selectNext();
  void selectPrev();
  String? accept();   // returns inserted text or null
  void dismiss();
}
```

**Gotchas:**
- `ShellAutocomplete.update` is async (subprocess); `SlashAutocomplete.update` is sync — interface must be async-friendly
- `AtFileHint` caches directory listings — keep cache private
- Overlaps with existing task-2 (nushell/reedline spike); if reedline is adopted later, it supersedes this work
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `AutocompleteOverlay` interface exists at `cli/lib/src/ui/autocomplete_overlay.dart`
- [ ] #2 All three overlays implement it
- [ ] #3 `terminal_event_router.dart` uses polymorphism (no `if (x.active) else if (y.active)` chain)
- [ ] #4 User-visible behavior unchanged
- [ ] #5 Tests cover each overlay via the unified interface
- [ ] #6 `dart analyze --fatal-infos` clean; `dart test` green
<!-- AC:END -->
