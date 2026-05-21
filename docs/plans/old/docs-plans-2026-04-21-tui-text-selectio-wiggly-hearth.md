# Implementation Plan — Double/Triple Click Word & Line Selection

Follow-up to the transcript-selection feature. Plan file: 2026-05-19.

## Context

Drag-to-select-and-copy ships today, but isolating a single identifier still requires a careful drag across exact cell boundaries. Standard editor convention is double-click to select a word and triple-click to select a line. The user wants both, with semantics that match the rest of the editor world.

The terminal mouse protocol doesn't report "double-click" — it always reports independent press/release pairs. We synthesize the click chain ourselves from timing + cell coordinates. Same approach used in `token-editor/src/runtime/mouse.rs` and every GUI editor.

## Word-boundary model — adopt token-editor's 3-class system

Three character classes:

| Class | Definition | Behaviour |
|---|---|---|
| **Whitespace** | `String.codeUnits` match `RegExp.unicode` whitespace (`\s`) | Selecting a whitespace run still works (it's a contiguous-class run) but produces an empty copy after trim. |
| **Punctuation** | Explicit ASCII set: `/ : , . - ( ) { } [ ] ; " ' < > = + * & \| ! @ # $ % ^ ~ ` \ ?` | Double-clicking `((` selects both parens; a lone `.` between identifiers selects just `.`. |
| **WordChar** | Everything else | Includes Unicode letters (CJK, accented), digits, `_`, emoji, combining marks. |

This matches `token-editor/src/util/text.rs:42-60` (`CharType` enum) and is functionally equivalent to VS Code's `editor.wordSeparators` default. Selection algorithm: at the click position, determine the class of the char under the cursor, then expand left and right while neighbouring chars share that class.

Rationale for matching token-editor exactly: the user already has muscle memory for that editor; cross-tool consistency beats theoretical purity. Implementation is a near-1:1 port of `is_punctuation` + `char_type` + `select_word` (~30 LOC of Dart).

## Click-chain detection

State held in App (or a small `ClickChain` helper in `cli/lib/src/app/transcript_selection.dart`):

```dart
class ClickChain {
  static const Duration window = Duration(milliseconds: 300);
  DateTime? _lastAt;
  int _lastX = 0, _lastY = 0;
  int _count = 0;

  /// Returns the new click count (1, 2, or 3, then wraps to 1).
  /// Resets when too slow OR when the cell moved at all.
  int register(int x, int y, DateTime now) {
    final last = _lastAt;
    final rapid = last != null && now.difference(last) <= window;
    final sameCell = x == _lastX && y == _lastY;
    _count = rapid && sameCell && _count < 3 ? _count + 1 : 1;
    _lastAt = now;
    _lastX = x;
    _lastY = y;
    return _count;
  }

  void reset() { _count = 0; _lastAt = null; }
}
```

300ms window (matches token-editor at `runtime/mouse.rs:50`). Cell-exact, no Manhattan slop — terminals report integer cells, the protocol's already discrete enough.

Reset triggers:
- `_handleMousePress` when the press starts a drag (drag mode overrides chain).
- `_handleMouseRelease` when the gesture was a drag (drag invalidates accumulated clicks).

## Selection helpers

Add to `cli/lib/src/app/transcript_selection.dart`:

```dart
enum CharClass { whitespace, word, punctuation }

CharClass classify(int rune) {
  if (_isWhitespace(rune)) return CharClass.whitespace;
  if (_isPunctuation(rune)) return CharClass.punctuation;
  return CharClass.word;
}

/// Find the contiguous same-class run containing [offset] in [plain].
/// Returns (start, endExclusive). For empty strings or out-of-range
/// offsets, returns (0, 0) — caller treats as "no selection".
(int, int) findClassRange(String plain, int offset) { … }
```

Punctuation set ported verbatim from `token-editor/src/util/text.rs:4-38`:
`/ : , . - ( ) { } [ ] ; " ' < > = + * & | ! @ # $ % ^ ~ ` \ ?`

For line selection, a trivial helper that returns the rendered-line range:

```dart
/// Range covering the rendered line at [visibleLineIdx] (block-relative).
(TranscriptPosition, TranscriptPosition)? lineRangeAt(...) { … }
```

Lives in `App` rather than `transcript_selection.dart` since it needs the per-frame `_outputLineAnchors` and `_plainOutputLines` shadow.

## Wiring into the existing mouse pipeline

`cli/lib/src/app.dart` — touch only `_handleMousePress` / `_handleMouseRelease` / `_handleOutputClick`. Adds a single field `final ClickChain _clickChain = ClickChain();`.

`_handleMouseRelease` becomes:

```dart
void _handleMouseRelease(MouseEvent event) {
  final drag = _dragState;
  _dragState = null;
  if (drag == null) return;

  if (drag.exceededThreshold) {
    // existing drag-finalise + copy path
    _clickChain.reset();
    final endPos = _resolvePositionAt(event.x, event.y);
    if (endPos != null && _selection != null) {
      _selection = _selection!.withFocus(endPos);
    }
    copySelectionToClipboard();
    return;
  }

  // It's a click — figure out which kind in the chain.
  final count = _clickChain.register(event.x, event.y, DateTime.now());
  switch (count) {
    case 1:
      _handleOutputClick(event.y); // existing subagent-group toggle
    case 2:
      _selectWordAt(event.x, event.y);
    case 3:
      _selectLineAt(event.y);
  }
}
```

`_selectWordAt` / `_selectLineAt`:

1. Resolve the click to `(blockId, plainTextOffset)` via existing `_resolvePositionAt`.
2. Look up the block's plain text in `_blockPlainText` (word) or the visible line's plain text via `_outputLineAnchors[idx]` + `_plainOutputLines[idx]` (line).
3. Compute the (start, end) range.
4. Build `TranscriptSelection(anchor: (blockId, start), focus: (blockId, end))`.
5. Call `copySelectionToClipboard()`. Existing toast confirms.

Selection stays highlighted until Esc or next press — same as drag-select.

## Files to modify

| Path | Change |
|---|---|
| `cli/lib/src/app/transcript_selection.dart` | Add `CharClass`, `classify`, `findClassRange`, `ClickChain`. |
| `cli/lib/src/app.dart` | Add `_clickChain` field; extend `_handleMouseRelease` with click-count dispatch; add `_selectWordAt` and `_selectLineAt`. Reset chain on drag-start and after drag-release. |
| `cli/lib/glue.dart` | Export the new selection helpers (for tests). |
| `cli/test/app/transcript_selection_test.dart` | Add tests for `classify`, `findClassRange`, `ClickChain.register`. |

No changes to the terminal layer (mouse parsing), rendering pipeline, clipboard, or toast — all reused.

## Edge cases

1. **Click on a subagent-group line** — first click toggles the group (existing behaviour). Second click (within 300ms, same cell) selects the word *on the now-changed line*. Acceptable: the line index hasn't changed, the click coord hasn't changed, the toggle re-renders but the chain machinery doesn't care.
2. **Word selection on non-selectable rows** (modal lines, blank separators, sentinel pseudo-blocks during streaming) — `_resolvePositionAt` returns `null` → no selection, chain still increments. Predictable.
3. **Click chain across re-render** — the chain only cares about (x, y, time). Re-renders between clicks don't reset it. Correct.
4. **Wide glyphs** — clicking on cell 5 of a 2-cell `漢` resolves to the char offset of `漢` via existing `_colToCharOffset`; `classify(rune of 漢)` returns `word`; expansion picks up adjacent CJK letters. Works without special-casing.
5. **Triple-click on an empty line** — line is `""`; `lineRangeAt` returns an empty range; `copySelectionToClipboard` short-circuits on `text.isEmpty`. No toast. Quiet.
6. **Click chain after a drag** — drag-release resets the chain. So drag → quick click won't accidentally promote to double-click.
7. **Click chain timeout that crosses the 300ms boundary during a re-render burst** — `DateTime.now()` is wall-clock so a paused isolate doesn't fake-elapse time. Safe.

## Tests

`cli/test/app/transcript_selection_test.dart` — new groups:

- `classify` returns `whitespace` for `' '`, `'\t'`; `punctuation` for each char in the explicit set; `word` for letters, digits, `_`, CJK `中`, emoji `😀`, combining mark.
- `findClassRange` on:
  - `"foo_bar baz"` at offset 4 → `(0, 7)` (selects `foo_bar`).
  - `"foo.bar"` at offset 3 → `(3, 4)` (selects just `.`).
  - `"(()"` at offset 0 → `(0, 2)` (selects `((`).
  - `"   "` at offset 1 → `(0, 3)` (whitespace run; trimmed-empty copy).
  - `"漢字"` at offset 0 → `(0, 2)`.
  - empty string → `(0, 0)`.
  - offset out of range → clamped, returns valid range.
- `ClickChain.register`:
  - Two clicks <300ms apart at the same cell → counts 1 then 2.
  - Three rapid clicks at the same cell → counts 1, 2, 3; fourth wraps to 1.
  - Two clicks >300ms apart → resets to 1.
  - Two clicks at adjacent cells → resets to 1 (cell-exact).
  - `reset()` zeroes the count and timestamp.

Smoke verification (manual):

1. `just cli::check` passes.
2. Build the binary; in a session, double-click in the middle of an identifier like `_handleMouseRelease` → just that identifier highlights and the toast confirms.
3. Double-click on `.` between `foo.bar` → just `.` is selected.
4. Triple-click anywhere on a line → whole rendered line highlights + copies.
5. Single-click on a subagent-group line still toggles the group; double-click on the same line toggles once then selects the word at that cell.
6. Drag-select still works; doing a slow drag then a single click resets the chain (next click is a 1).
7. Click on whitespace between words → whitespace selected but the resulting copy is empty (no toast).

## Out of scope (deferred)

- Double-click + drag = word-by-word selection extension (VS Code/Zed feature). Material complexity for low payoff.
- Configurable word characters per language/file extension.
- Keyboard equivalents (`Ctrl+W` select-word, etc.).
- Selecting inside the input editor / modals / docked panels.

## Reuse summary

| Existing primitive | File | Used as-is |
|---|---|---|
| `TranscriptPosition` / `TranscriptSelection` | `cli/lib/src/app/transcript_selection.dart` | anchor + focus for word/line ranges |
| `_resolvePositionAt` | `cli/lib/src/app.dart` | screen `(x,y)` → block + offset |
| `_blockPlainText` shadow | `cli/lib/src/app.dart` | plain text for word range walk |
| `_outputLineAnchors` + `_plainOutputLines` | `cli/lib/src/app.dart` | per-visible-line plain text for line selection |
| `copySelectionToClipboard` | `cli/lib/src/app.dart` | finishing the gesture + toast |
| `applySelectionHighlight` | `cli/lib/src/rendering/ansi_utils.dart` | rendering the new highlight |
| `DragState` threshold + arbitration | `cli/lib/src/app/transcript_selection.dart` | unchanged; gates click vs drag path |
| Punctuation set + 3-class model | ported from `~/code/token-editor/src/util/text.rs:4-60` | identical semantics, Dart port |
| Click tracker shape | ported from `~/code/token-editor/src/runtime/mouse.rs:27-81` | 300ms window, cell-exact |
