---
id: TASK-21
title: Unified AutocompleteOverlay interface
status: Done
assignee: []
created_date: '2026-04-19 00:34'
updated_date: '2026-04-20 00:32'
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
ordinal: 33000
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
- [x] #1 `AutocompleteOverlay` interface exists at `cli/lib/src/ui/autocomplete_overlay.dart`
- [x] #2 All three overlays implement it
- [x] #3 `terminal_event_router.dart` uses polymorphism (no `if (x.active) else if (y.active)` chain)
- [x] #4 User-visible behavior unchanged
- [x] #5 Tests cover each overlay via the unified interface
- [x] #6 `dart analyze --fatal-infos` clean; `dart test` green
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
### Interface

New file `cli/lib/src/ui/autocomplete_overlay.dart`:

```dart
class AcceptResult {
  final String text;    // full new buffer content
  final int cursor;     // absolute cursor position in `text`
  const AcceptResult(this.text, this.cursor);
}

abstract class AutocompleteOverlay {
  bool get active;
  int get selected;
  int get matchCount;
  int get overlayHeight;
  void moveUp();
  void moveDown();
  /// Accept the current selection given the current editor [buffer] and [cursor].
  /// Returns the new buffer + cursor, or null if nothing to accept.
  AcceptResult? accept(String buffer, int cursor);
  void dismiss();
  List<String> render(int width);
}
```

`update` is NOT on the interface because trigger semantics differ across overlays (slash/atfile react to every buffer change; shell waits for Tab). Each overlay keeps its own `update`/`requestCompletions` entry point; the router calls the right one at the right moment.

### Impl updates

- **SlashAutocomplete**: `accept()` currently returns `String?` (`/help`). Change to `AcceptResult?` with the full command and cursor at end. `update(buffer, cursor)` stays sync.
- **ShellAutocomplete**: already returns `({String text, int cursor})?` — wrap into `AcceptResult`. `requestCompletions` stays as-is (async, Tab-triggered).
- **AtFileHint**: `accept()` currently returns `String?` and relies on the caller to splice. Move splice logic inside by having `accept(buffer, cursor)` use the cached `_tokenStart` and cursor to compute the new buffer + cursor.

### Router collapse

`cli/lib/src/app/terminal_event_router.dart` currently has three near-identical blocks (slash/shell/atfile) each matching Up/Down/Tab/Enter/Esc. Replace with a single helper:

```dart
final active = [app._autocomplete, app._shellComplete, app._atHint]
    .firstWhereOrNull((o) => o.active);
if (active != null) {
  // handle key events polymorphically via interface
}
```

Preserves per-overlay quirks only where absolutely necessary (e.g. the shell's Tab re-triggers `requestCompletions` vs slash/atfile's Tab accepting).

### Tests

Add `cli/test/ui/autocomplete_overlay_test.dart` that exercises each impl through the interface for:
- moveUp/moveDown wrapping
- dismiss()
- accept(buffer, cursor) → AcceptResult shape

Verify existing tests still pass after the signature change (slash + atfile tests that assert on `String?` from `accept()` need updating).
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
New file `cli/lib/src/ui/autocomplete_overlay.dart` defines:
- `AcceptResult { text, cursor }` — final buffer + cursor after accept
- `AutocompleteOverlay` — abstract contract: `active`, `selected`, `matchCount`, `overlayHeight`, `moveUp`, `moveDown`, `accept(buffer, cursor)`, `dismiss`, `render(width)`

Each overlay implements the interface and keeps its own trigger entry point:
- `SlashAutocomplete` → sync `update(buffer, cursor)` on every buffer change
- `ShellAutocomplete` → async `requestCompletions(buffer, cursor)` on Tab
- `AtFileHint` → sync `update(buffer, cursor)` on every buffer change

`terminal_event_router.dart` collapses the three near-identical key-handling chains into one polymorphic dispatch:

```dart
AutocompleteOverlay? activeOverlay;
for (final o in <AutocompleteOverlay>[
  app._autocomplete, app._shellComplete, app._atHint,
]) {
  if (o.active) { activeOverlay = o; break; }
}
if (activeOverlay != null) { /* Up/Down/Tab/Enter/Esc */ }
```

The only non-uniform quirk preserved: SlashAutocomplete's Enter-on-exact-match falls through to submit instead of re-accepting.

`AtFileHint.accept` now splices internally (was previously splicing in the router). Bug caught during testing: `dismiss()` was clearing `_tokenStart` before the splice read it — captured in a local first.

Also:
- `lib/src/input/streaming_input_handler.dart` updated to the new `accept(buffer, cursor) → AcceptResult?` shape
- `lib/glue.dart` barrel exports `AutocompleteOverlay` and `AcceptResult`
- Existing tests for each overlay updated to new signature
- New `test/ui/autocomplete_overlay_test.dart` exercises each impl through the abstract type

Verification: `dart analyze --fatal-infos lib/` clean, `dart format` clean, full test suite (`dart test`) = 1157 pass / 0 failed. (`test/catalog/*` analyze warnings exist but belong to task-22 (parallel work).)
<!-- SECTION:FINAL_SUMMARY:END -->
