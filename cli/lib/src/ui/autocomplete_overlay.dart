import 'package:glue_core/glue_core.dart';

/// Result of accepting an autocomplete suggestion.
///
/// Represents the full new buffer contents and the absolute cursor
/// position within it. Each overlay computes its own splicing strategy
/// and returns the result, so the router can apply it uniformly with
/// `editor.setText(result.text, cursor: result.cursor)`.
class AcceptResult {
  final String text;
  final int cursor;
  const AcceptResult(this.text, this.cursor);
}

/// Common contract for in-input autocomplete overlays.
///
/// Three implementations live in `cli/lib/src/ui/`:
/// - [SlashAutocomplete] — command palette triggered by `/`
/// - [ShellAutocomplete] — tab completion triggered inside bash mode
/// - [AtFileHint] — `@file` reference hint
///
/// The router dispatches Up/Down/Tab/Enter/Esc to whichever overlay is
/// currently [active]. Trigger semantics (how an overlay becomes active
/// in the first place) differ per overlay and are NOT part of this
/// interface — each overlay keeps its own `update`/`requestCompletions`
/// entry point.
abstract class AutocompleteOverlay {
  /// Whether the overlay is currently shown and intercepting input.
  bool get active;

  /// Index of the currently highlighted match.
  int get selected;

  /// Number of matches currently displayed.
  int get matchCount;

  /// Rows the overlay occupies when rendered.
  int get overlayHeight;

  /// Move selection up (wraps).
  void moveUp();

  /// Move selection down (wraps).
  void moveDown();

  /// Accept the current selection, given the editor's current [buffer]
  /// and absolute [cursor] position. Returns the new buffer + cursor,
  /// or null if nothing to accept.
  AcceptResult? accept(String buffer, int cursor);

  /// Hide the overlay and reset state.
  void dismiss();

  /// Render the overlay as styled lines for the given [width].
  List<String> render(int width);
}

/// Selection and viewport state shared by the three overlays.
///
/// They differ entirely in how they build their match list and not at all
/// in how the user moves through it, so [moveUp], [moveDown], the scroll
/// clamp and [overlayHeight] live here. Implementers supply [matchCount]
/// and reset the cursor with [resetSelection] whenever the list changes.
mixin AutocompleteSelection {
  /// Number of matches currently displayed.
  int get matchCount;

  int _selected = 0;
  int _scrollOffset = 0;

  /// Index of the currently highlighted match.
  int get selected => _selected;

  /// First match index visible in the render window.
  int get scrollOffset => _scrollOffset;

  /// Rows the overlay occupies: the match count, capped at one screenful.
  int get overlayHeight => matchCount > AppConstants.maxVisibleDropdownItems
      ? AppConstants.maxVisibleDropdownItems
      : matchCount;

  /// Put the cursor back at the top. Call after rebuilding the match list.
  void resetSelection() {
    _selected = 0;
    _scrollOffset = 0;
  }

  /// Keep the selection in range after the match list was rebuilt, and put
  /// the render window back at the top.
  void clampSelectionToMatches() {
    if (matchCount == 0) return resetSelection();
    _selected = _selected.clamp(0, matchCount - 1);
    _scrollOffset = 0;
    clampScroll();
  }

  void moveUp() {
    if (matchCount == 0) return;
    // Dart's `%` is never negative for a positive divisor, so this wraps
    // to the last entry without a correction step.
    _selected = (_selected - 1) % matchCount;
    clampScroll();
  }

  void moveDown() {
    if (matchCount == 0) return;
    _selected = (_selected + 1) % matchCount;
    clampScroll();
  }

  /// Slide the render window so [selected] stays inside it.
  void clampScroll() {
    const maxVisible = AppConstants.maxVisibleDropdownItems;
    if (_selected < _scrollOffset) {
      _scrollOffset = _selected;
    } else if (_selected >= _scrollOffset + maxVisible) {
      _scrollOffset = _selected - maxVisible + 1;
    }
    _scrollOffset = _scrollOffset.clamp(
      0,
      (matchCount - maxVisible).clamp(0, matchCount),
    );
  }
}
