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
