# TUI Text Selection and Copy Plan

Status: proposed
Owner: implementation agent
Date: 2026-04-21

## Goal

Investigate how Glue can support selecting text inside the TUI for copy/paste,
using AmpCode / OpenCode style fullscreen TUIs as reference points, and define a
safe implementation plan that fits Glue’s current architecture.

The concrete user problem is simple:

- users want to copy text from the conversation
- today Glue runs in alternate screen and enables mouse capture
- that blocks or degrades native terminal selection in many terminals
- the result is that chat/tool output is harder to reuse than it should be

This plan covers both:

1. what comparable TUIs appear to do
2. what Glue should implement first vs later

## Executive Summary

Short version after re-checking Glue’s actual architecture:

1. **A pure “mouse off” solution is not enough for Glue’s goals.**
   It is true that disabling mouse capture would restore native terminal
   selection in many environments, and OpenCode exposes exactly that. But in
   Glue, mouse input is already part of the product surface:
   - mouse wheel scrolls transcript
   - clicks in output toggle expandable transcript groups
   - panels and overlays assume Glue owns input routing in alternate screen

   So simply turning mouse off globally would be a usability regression, not a
   complete solution.

2. **The right feature to build is real in-app transcript selection.**
   That is closer to the Claude fullscreen / AmpCode class of UX and better
   matches Glue’s current architecture, where the app already owns scrolling,
   rendering, viewport state, and clipboard integration.

3. **Glue is closer to supporting selection than the first draft assumed.**
   The render pipeline already reconstructs the visible transcript each frame.
   The biggest missing piece is not a brand new subsystem; it is a more
   structured representation of rendered transcript lines so hit-testing,
   highlighting, and plain-text extraction are safe.

4. **The minimal shippable version should be narrower than the reference UIs.**
   First version should support:
   - drag-select in the main transcript only
   - plain-text copy on mouse release
   - `Esc` to clear selection
   - `Ctrl+C` copies when a selection is active, otherwise existing
     cancel/exit behavior remains

   It should explicitly skip, at first:
   - input-area selection
   - panel/modal selection
   - double/triple click word/line selection
   - keyboard range extension
   - transcript export/review mode
   - config/command surface like `/mouse on|off`

5. **Recommendation:** revise the plan around transcript selection first.\*\*
   - **Phase 1:** add internal rendered-line model + selection state + drag
     selection in transcript
   - **Phase 2:** polish interactions (`Ctrl+C`, `Esc`, click-vs-drag
     arbitration, maybe auto-copy toast)
   - **Phase 3:** optional enhancements like review/export mode or word/line
     selection

That is a better fit for how Glue already works today.

## External Findings

## OpenCode

From the OpenCode TUI docs:

- `mouse` is a TUI config option
- default is `true`
- when disabled, the terminal’s native mouse selection/scrolling behavior is
  preserved

This is the clearest relevant precedent because it addresses the exact UX issue:
users inside alternate-screen/fullscreen TUI apps still need a straightforward
way to copy text using their terminal/multiplexer’s native behavior.

There is also a public issue requesting this specifically for terminal
multiplexer compatibility:

- mouse capture prevents normal selection in tmux/Zellij-style environments
- `Shift+mouse` is only a partial workaround
- users want an explicit option to disable mouse capture entirely

That suggests a strong product lesson:

> even if we later implement in-app selection, we should still support disabling
> mouse capture because native terminal selection remains valuable and expected.

## Claude fullscreen / AmpCode-style reference

The most detailed public reference available in this investigation is Claude
Code’s fullscreen rendering docs, which are representative of the same class of
alternate-screen coding TUIs.

Documented behaviors:

- click in input to place the cursor
- click collapsed items to expand/collapse
- click URLs/file paths to open them
- click-drag to select text anywhere in the conversation
- double-click selects word
- triple-click selects line
- selected text copies automatically on mouse release
- optional “copy on select” setting
- manual copy shortcut if copy-on-select is off
- when selection is active, `Ctrl+C` copies instead of cancelling
- `Shift+Arrow`, `Shift+Home`, `Shift+End` extend selection from keyboard
- mouse wheel scrolls viewport
- transcript/review mode can write conversation into terminal scrollback so
  native search/copy tools work again
- mouse capture can still be turned off while keeping fullscreen rendering

This is important because it shows the full feature shape if Glue eventually
wants first-class in-app selection. But it also reinforces that these products
still preserve an escape hatch back to native terminal behaviors.

## Key product insight from references

There are really **three** valid copy workflows in fullscreen TUIs:

1. **Native terminal selection**
   - simplest
   - best for tmux/Zellij/terminal power users
   - requires disabling or bypassing mouse capture

2. **In-app transcript export/review mode**
   - useful for search/select in long conversations
   - avoids building a complete selection engine first

3. **True in-app selection**
   - best integrated UX
   - most technically complex

Glue should probably support all three eventually, but not all at once.

## Current Glue State

Relevant current behavior from the codebase after a closer pass:

### Terminal control

`cli/lib/src/terminal/terminal.dart`

Glue currently:

- enters raw mode
- enters alternate screen
- enables mouse reporting via:

```dart
void enableMouse() => write('\x1b[?1000h\x1b[?1006h');
```

- disables mouse reporting on shutdown
- parses SGR mouse events into `MouseEvent(x, y, button, isDown: ...)`

Current mouse parsing supports:

- button press/release information
- wheel detection
- coordinates

But it does **not** yet expose a richer event model like:

- drag / motion tracking
- modifier-state-aware mouse behavior
- click count semantics (single/double/triple)

### Event routing

`cli/lib/src/app/terminal_event_router.dart`

Current mouse handling is small but important:

- wheel scroll adjusts transcript scroll
- mouse press in output toggles subagent-group expand/collapse
- mouse handling already depends on transcript viewport math:
  - current visible top line is derived from `totalLines - viewportHeight - _scrollOffset`
  - click row is mapped into an output-line index
  - `_outputLineGroups` is used to recover which rendered lines belong to an
    expandable group

This matters because it means Glue already does basic transcript hit-testing.
Selection should reuse and generalize that idea instead of inventing a separate,
parallel coordinate system.

### Render pipeline

`cli/lib/src/app/render_pipeline.dart`

Glue already rebuilds a full rendered transcript every frame from `_blocks`.
That is the strongest architectural fact in favor of in-app selection.

Today the pipeline:

- renders each conversation block into text lines using `BlockRenderer`
- appends those lines into `outputLines`
- maintains a parallel `_outputLineGroups` list for clickable grouped regions
- computes the visible viewport from `_scrollOffset`
- slices visible lines and paints them via `Layout.paintOutputViewport`

This is a good base for selection because selection fundamentally operates over
rendered lines, not raw conversation objects.

More importantly, Glue is already paying the cost to derive those rendered lines
per frame. That means the most sensible selection architecture is:

- replace raw `List<String> outputLines` with a richer rendered-line structure
- keep deriving visible rows from the same viewport math
- add selection highlighting and plain-text extraction on top of those rendered
  rows

The missing pieces are therefore more specific than the first draft implied:

- rendered lines are not retained as structured records with both ANSI and
  plain-text forms
- there is no screen-column → visible-column → plain-text-offset mapping
- `_outputLineGroups` only tracks expand/collapse ownership, not text geometry
- `Layout.paintOutputViewport` only knows how to paint plain line strings, not
  selection ranges

### Clipboard support

Glue already has cross-platform clipboard writing:

- `cli/lib/src/core/clipboard.dart`

So copying selected text to clipboard is not a new platform problem. The missing
part is selecting the text and extracting a plain-text representation.

### Existing copy-related UX

Glue already supports copying certain discrete values/actions:

- session ID copy
- history item copy to clipboard
- device code auto-copy

So “copy to clipboard” as a product primitive already fits the app.

## Constraints and Design Implications

## 1. Alternate screen changes the default expectation

Because Glue uses alternate screen, terminal scrollback and native find/copy
behavior are already constrained. That means Glue cannot rely on “the terminal
already does selection” once mouse capture is enabled.

So if mouse capture stays on, Glue owns the copy UX.

## 2. Mouse capture conflicts with native terminal selection

Today Glue always enables mouse capture on startup:

```dart
terminal.enableMouse();
```

That blocks or interferes with click-drag selection in many terminals and
multiplexers.

So the shortest path to helping users is to make mouse capture optional.

## 3. Selection in a styled TUI is not just string slicing

Glue renders ANSI-styled lines. Selection needs to operate on visible columns,
not raw bytes/UTF-16 indices. That means:

- ANSI escapes must not count toward selection width
- wide glyphs must be handled consistently with existing width logic
- copied text should usually be plain text, not ANSI-coded text
- line wrapping matters because selection is over rendered lines

This is the core technical reason full in-app selection is non-trivial.

## 4. Mouse click actions already exist

Mouse press in output currently toggles subagent group expansion. If Glue adds
selection, single-click and drag behavior needs clear arbitration.

A likely rule set:

- drag gesture => selection
- plain click without movement => existing click action
- release after drag => copy / preserve selection

That means we need gesture classification, not just raw mouse-button events.

## 5. Keyboard semantics need thought

In coding-agent TUIs, `Ctrl+C` is already overloaded as cancel/exit. If Glue
adds selection, it should likely adopt the established behavior:

- when no selection is active: `Ctrl+C` keeps current cancel/exit behavior
- when selection is active: `Ctrl+C` copies selection and clears/preserves it

Without this, mouse selection alone will feel incomplete.

## Recommended Product Direction

## Recommendation A — build in-app transcript selection first

After looking more closely at Glue’s current TUI, this is the recommended first
implementation.

Why this is now the preferred answer:

- Glue already owns scrolling, viewporting, and mouse click behavior in the
  transcript
- mouse-off without a replacement would remove existing useful interactions
- clipboard support already exists
- the render pipeline is already centralized enough to support selection with a
  targeted refactor

So the real product question is not “should Glue let the terminal do it?” but:

> how do we add transcript selection to the TUI in a way that fits Glue’s
> current render pipeline?

## Recommendation B — keep transcript review/export as follow-up, not phase 1

A transcript export/review mode is still a good idea, but it is no longer the
recommended first milestone.

Why:

- the user asked specifically about selecting text inside the TUI
- Glue’s current app model is already closer to in-app selection than to a
  separate review-mode workflow
- review/export mode is additive polish, not the core missing interaction

## Recommendation C — do not add `/mouse` or config surface now

Given the current ask, we do not need:

- `/mouse on|off`
- persistent config for mouse capture
- a separate product surface for native-selection fallback

Those may still be reasonable later, especially for tmux/Zellij-heavy users, but
adding them now would expand surface area without solving the main problem.

## Initial in-app selection scope

Target behavior should be intentionally modest at first:

### Initial in-app selection scope

- click-drag to select text in the output transcript only
- selection copies plain text to clipboard on mouse release
- `Esc` clears selection
- `Ctrl+C` copies selection if active, otherwise preserves current cancel/exit
  behavior
- selection suppresses click-to-expand actions when drag distance exceeds a
  threshold

### Explicit non-goals for first in-app version

- selecting inside input/editor
- selecting inside panel overlays, modals, autocomplete, or docked panels
- rectangular/block selection
- word/line double-click and triple-click
- keyboard range extension
- transcript export/review mode
- OSC52 remote clipboard transport
- preserving ANSI styles in copied text

That smaller version is still useful and much more implementable.

## Architecture Recommendation for In-App Selection

If Glue implements in-app selection, it should not bolt selection directly onto
raw `outputLines` strings in an ad hoc way. The right foundation is a rendered
transcript model that fits directly into the current `render_pipeline.dart`
flow.

## Proposed model: rendered transcript lines as structured records

Add an internal render artifact close to:

```dart
class RenderedTranscriptLine {
  final String ansiText;
  final String plainText;
  final int visibleWidth;
  final _SubagentGroup? clickableGroup;
  final List<int> plainTextOffsetForColumn;
}
```

The important thing is not the exact type shape; it is that each rendered line
can answer:

- what ANSI text should be painted
- what plain text should be copied
- what transcript group, if any, owns the line for click actions
- how screen/visible columns map back to plain-text offsets

This should replace today’s split bookkeeping of:

- `List<String> outputLines`
- `List<_SubagentGroup?> _outputLineGroups`

with one coherent structure.

This solves multiple future needs, not just selection:

- accurate hit testing
- click-vs-drag arbitration
- selection highlighting
- plain-text extraction for clipboard copy
- later search highlighting or transcript export

## Required capabilities for in-app selection

### 1. Selection state

Add app state roughly like:

```dart
class TranscriptSelection {
  final TranscriptPosition anchor;
  final TranscriptPosition focus;
}

class TranscriptPosition {
  final int transcriptLine;
  final int column;
}
```

Also track transient drag state:

- mouse-down origin
- whether drag threshold has been crossed
- whether a click action should be suppressed on release

### 2. Mouse motion support

Current terminal mouse support enables press/release and wheel via:

- `?1000` button-event tracking
- `?1006` SGR coordinates

For drag-based selection, Glue will likely need motion reporting too.

That probably means extending terminal mouse mode to one of:

- `?1002` button-drag tracking
- or `?1003` all-motion tracking

`?1002` is the better likely starting point because Glue only needs movement
while a button is held, not arbitrary hover motion.

This is a concrete place where the first draft was too vague: the terminal layer
will need a real update, not just application-state changes.

### 3. Screen → transcript hit testing

Given a mouse `(x, y)` in output zone:

- map screen row into visible transcript line index using current viewport
- map screen column into visible column inside that rendered line
- clamp to end-of-line sensibly

### 4. Plain-text extraction

Clipboard copy should copy plain text, not ANSI text.

Need helpers to extract selected ranges across lines while:

- stripping ANSI
- preserving newlines between lines
- handling partially selected start/end lines

### 5. Visual highlight rendering

Selected ranges need to be re-rendered with reverse-video or theme selection
style.

This is slightly trickier in Glue than a generic string-highlighting pass,
because `Layout.paintOutputViewport()` currently accepts only `List<String>` and
just truncates/pads each line.

So one of these must happen:

- precompose each selected visible line into a final ANSI string before passing
  it to `paintOutputViewport()`, or
- teach `Layout` about richer rendered rows

For a minimal diff, precomposing final ANSI lines in `render_pipeline.dart`
looks more consistent with current architecture.

## Risks

## Risk 1: implementing selection before a transcript model

If selection is implemented directly over raw rendered strings, it will likely
become fragile around:

- ANSI styling
- wide characters
- wrapped markdown/code blocks
- future search highlighting
- clickable spans

Recommendation: build the transcript-layout abstraction first.

## Risk 2: regression in click interactions

Current output clicks toggle grouped transcript items. Selection drag can easily
break or make these actions noisy.

Recommendation: define gesture arbitration explicitly:

- mouse-down starts pending gesture
- if pointer moves beyond threshold => selection mode
- if pointer does not move beyond threshold => click action

## Risk 3: terminal compatibility

Mouse-motion reporting behaves differently across terminals/multiplexers. Some
users will still prefer native selection.

Recommendation: mouse-capture-off mode remains a first-class supported path even
after in-app selection ships.

## Risk 4: `Ctrl+C` semantic conflicts

Glue uses `Ctrl+C` for cancel/exit. Copying selected text with `Ctrl+C` is a
well-established expectation.

Recommendation: selection-active override only.

## Proposed UX Surface

For the revised plan, keep the user-facing surface minimal.

## Initial UX

When transcript selection ships, document behavior clearly:

- drag in output to select
- release copies selected plain text to clipboard
- `Esc` clears selection
- `Ctrl+C` copies selection if one is active; otherwise Glue keeps existing
  cancel/exit behavior

## No new config or command surface in the first pass

Do not add, initially:

- `/mouse`
- `/mouse on|off`
- persistent config for mouse capture behavior

Reason:

- the ask is specifically about selecting text in the TUI
- Glue already commits to mouse-enabled fullscreen interaction
- adding config/command surface now would increase scope without helping the
  core implementation

## Recommended Implementation Plan

## Phase 1 — Internal rendered transcript model

### Scope

Refactor the render pipeline so transcript rows are represented as structured
rendered lines instead of bare strings plus parallel group metadata.

### Files likely involved

- `cli/lib/src/app.dart`
- `cli/lib/src/app/render_pipeline.dart`
- `cli/lib/src/rendering/ansi_utils.dart`
- possibly a new helper under `cli/lib/src/app/` or `cli/lib/src/rendering/`

### Behavior

- replace `List<String> outputLines` + `_outputLineGroups` parallel bookkeeping
  with a richer rendered-line structure
- each rendered line carries:
  - final ANSI text
  - plain-text form
  - visible-width mapping info
  - clickable group ownership if applicable
- visible viewport logic stays the same conceptually

### Acceptance criteria

- no UI behavior changes yet
- existing transcript rendering remains visually identical
- expandable subagent-group click behavior still works through the new row
  model
- the app now has enough data to do safe hit-testing and text extraction

## Phase 2 — Transcript selection state and drag handling

### Scope

Add drag-based selection in the main output transcript only.

### Files likely involved

- `cli/lib/src/terminal/terminal.dart`
- `cli/lib/src/app.dart`
- `cli/lib/src/app/terminal_event_router.dart`
- `cli/lib/src/app/render_pipeline.dart`

### Behavior

1. add selection state to `App`
2. extend terminal mouse reporting to include drag motion while button is held
3. on mouse-down in output zone, begin a pending gesture
4. if pointer moves beyond threshold, convert gesture into a selection
5. on mouse-up after a drag, copy selected plain text to clipboard
6. if no drag occurred, preserve existing click behavior for expandable groups

### Acceptance criteria

- user can drag-select visible transcript text
- copied clipboard content is plain text
- click-to-expand still works when there was no drag gesture
- selection is limited to the main transcript area only

## Phase 3 — Selection polish and keyboard semantics

### Scope

Make selection feel native inside Glue without broadening scope into a full text
editor selection system.

### Files likely involved

- `cli/lib/src/app/terminal_event_router.dart`
- `cli/lib/src/input/streaming_input_handler.dart`
- `cli/lib/src/app/render_pipeline.dart`
- `cli/lib/src/core/clipboard.dart`

### Behavior

- `Esc` clears active transcript selection before doing anything else
- `Ctrl+C` copies selection when one is active; otherwise existing
  cancel/exit/cancel-agent behavior remains
- add a lightweight system confirmation or status hint after copy if needed
- keep selection stable while viewport is stable

### Acceptance criteria

- `Esc` predictably clears selection
- `Ctrl+C` selection-copy does not break current interrupt semantics when no
  selection exists
- selected ranges remain visually highlighted until cleared or replaced

## Phase 4 — Optional follow-up enhancements

### Candidates

- transcript review/export mode
- double-click word selection
- triple-click line selection
- keyboard extension of selection
- selection in panels/modals

## Open Questions

## Should Glue support a mouse-disable escape hatch later?

Maybe, but not needed for the first implementation.

OpenCode suggests it is useful, especially for multiplexers, but it is not
required to solve the core Glue problem.

## Should selection auto-copy on release?

Yes, probably.

That is the most direct fit for the requested copy workflow and avoids needing a
new copy command surface. Glue already has clipboard support, so release-to-copy
is the simplest end-to-end interaction.

## Should we support selection in panels/modals too?

Not initially.

Start with main transcript only.

## Final Recommendation

Implement this as a transcript-selection feature, not as a mouse-toggle feature.

Recommended sequence:

1. **Introduce a structured rendered transcript line model** inside the current
   render pipeline.
2. **Add drag-based transcript selection and plain-text clipboard copy.**
3. **Polish selection semantics** (`Esc`, `Ctrl+C`, click-vs-drag arbitration).
4. Treat export/review mode and mouse-disable escape hatches as optional later
   work.

That sequence better matches:

- the user’s actual ask
- Glue’s current ownership of mouse interaction in the TUI
- the existing render pipeline architecture
- the reference fullscreen TUI behavior we want to approximate

## Concrete Decision

### Decision A — recommended

Build true in-app transcript selection on top of a structured rendered-line
model.

### Decision B — acceptable follow-up

Later add review/export mode or a mouse-disable escape hatch if users still need
native terminal workflows.

### Decision C — not recommended

Attempt to hack drag selection directly onto current raw rendered strings and
parallel `_outputLineGroups` bookkeeping.

Decision C should be rejected.
