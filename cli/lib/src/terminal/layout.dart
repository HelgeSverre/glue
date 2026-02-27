import '../rendering/ansi_utils.dart';
import 'terminal.dart';

/// Divides the terminal into vertical zones that cooperate using
/// ANSI scroll regions:
///
/// ```
/// ┌──────────────────────────────┐
/// │  Output Zone (scrollable)    │ ← uses terminal's native scroll
/// │  ...                         │
/// ├──────────────────────────────┤
/// │  Overlay Zone (0-N lines)    │ ← autocomplete popup, etc.
/// ├──────────────────────────────┤
/// │  Status Bar (1 line, fixed)  │ ← painted at fixed row
/// ├──────────────────────────────┤
/// │  Input Zone (1-N lines)      │ ← painted at bottom
/// └──────────────────────────────┘
/// ```
///
/// The scroll region trick keeps output scrolling naturally while the
/// overlay, status bar, and input area stay pinned.
class Layout {
  final Terminal terminal;

  final int _statusHeight = 1;
  int _inputHeight = 1;
  int _overlayHeight = 0;

  Layout(this.terminal);

  // ── Zone boundaries (1-indexed rows) ──────────────────────────────────

  /// First row of the scrollable output zone.
  int get outputTop => 1;

  /// Last row of the scrollable output zone.
  int get outputBottom =>
      (terminal.rows - _statusHeight - _inputHeight - _overlayHeight)
          .clamp(outputTop, terminal.rows);

  /// First row of the overlay zone (between output and status bar).
  int get overlayTop => outputBottom + 1;

  /// Last row of the overlay zone.
  int get overlayBottom => overlayTop + _overlayHeight - 1;

  /// Row where the status bar is painted.
  int get statusRow => terminal.rows - _inputHeight;

  /// First row of the input area.
  int get inputTop => terminal.rows - _inputHeight + 1;

  /// Last row of the input area.
  int get inputBottom => terminal.rows;

  // ── Configuration ─────────────────────────────────────────────────────

  /// Apply (or re-apply) the hardware scroll region so that text printed
  /// inside the output zone scrolls without disturbing the status bar or
  /// input area.
  void apply() {
    if (outputBottom > outputTop) {
      terminal.setScrollRegion(outputTop, outputBottom);
    }
  }

  /// Update the input zone height (e.g. for multi-line editing).
  void setInputHeight(int lines) {
    _inputHeight = lines.clamp(1, terminal.rows ~/ 3);
    apply();
  }

  /// Update the overlay zone height. Call before rendering.
  ///
  /// Only calls [apply] if the height actually changed to avoid flicker.
  void setOverlayHeight(int lines) {
    final clamped = lines.clamp(0, terminal.rows ~/ 3);
    if (clamped == _overlayHeight) return;
    _overlayHeight = clamped;
    apply();
  }

  // ── Zone rendering helpers ────────────────────────────────────────────

  /// Paint the output zone with pre-computed lines for scrollback.
  void paintOutputViewport(List<String> lines) {
    final height = outputBottom - outputTop + 1;
    for (var i = 0; i < height; i++) {
      terminal.moveTo(outputTop + i, 1);
      terminal.clearLine();
      if (i < lines.length) {
        terminal.write(lines[i]);
      }
    }
  }

  /// Append [text] to the output zone (scrolls naturally within the
  /// scroll region).
  void writeOutput(String text) {
    terminal.saveCursor();
    terminal.moveTo(outputBottom, 1);
    terminal.write('\n$text');
    terminal.restoreCursor();
  }

  /// Paint the overlay zone with pre-rendered lines.
  void paintOverlay(List<String> lines) {
    for (var i = 0; i < _overlayHeight; i++) {
      terminal.moveTo(overlayTop + i, 1);
      terminal.clearLine();
      if (i < lines.length) {
        terminal.write(lines[i]);
      }
    }
  }

  /// Paint the status bar at its fixed row.
  ///
  /// [left] is shown left-aligned and [right] is shown right-aligned.
  void paintStatus(String left, String right) {
    terminal.moveTo(statusRow, 1);
    terminal.clearLine();

    final leftVisible = visibleLength(left);
    final rightVisible = visibleLength(right);
    final padding = terminal.columns - leftVisible - rightVisible;
    terminal.writeStyled(
      '$left${' ' * padding.clamp(0, 9999)}$right',
      style: AnsiStyle.inverse,
    );
  }

  /// Paint the input area showing [prompt] followed by [text] with the
  /// cursor positioned at [cursorPos] within the text.
  void paintInput(String prompt, String text, int cursorPos, {bool showCursor = true}) {
    terminal.moveTo(inputTop, 1);
    terminal.clearLine();
    terminal.writeStyled(prompt, style: AnsiStyle.yellow);
    terminal.write(text);

    // Fill rest of line with spaces to clear stale characters.
    final usedCols = prompt.length + text.length;
    if (usedCols < terminal.columns) {
      terminal.write(' ' * (terminal.columns - usedCols));
    }

    // Position the visible cursor where the user is typing.
    final cursorCol = (prompt.length + cursorPos + 1).clamp(1, terminal.columns);
    terminal.moveTo(inputTop, cursorCol);
    if (showCursor) terminal.showCursor();
  }
}
