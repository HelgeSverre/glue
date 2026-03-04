import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/config/constants.dart';
import 'package:glue/src/terminal/terminal.dart';

/// Divides the terminal into vertical zones that cooperate using
/// ANSI scroll regions.
///
/// {@category Terminal & Rendering}
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
  int _dockLeft = 0;
  int _dockRight = 0;
  int _dockTop = 0;
  int _dockBottom = 0;

  Layout(this.terminal);

  // ── Zone boundaries (1-indexed rows) ──────────────────────────────────

  /// First row of the scrollable output zone.
  int get outputTop => 1 + _dockTop;

  /// Last row of the scrollable output zone.
  int get outputBottom => (terminal.rows -
          _statusHeight -
          _inputHeight -
          _overlayHeight -
          _dockBottom)
      .clamp(outputTop, terminal.rows);

  /// Left column of the scrollable output zone.
  int get outputLeft => 1 + _dockLeft;

  /// Right column of the scrollable output zone.
  int get outputRight =>
      (terminal.columns - _dockRight).clamp(outputLeft, terminal.columns);

  /// Width of the output zone.
  int get outputWidth => outputRight - outputLeft + 1;

  /// Height of the output zone.
  int get outputHeight => outputBottom - outputTop + 1;

  /// First row of the overlay zone (between output and status bar).
  int get overlayTop => outputBottom + _dockBottom + 1;

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
    _inputHeight =
        lines.clamp(1, terminal.rows ~/ AppConstants.inputAreaDivisor);
    apply();
  }

  /// Update dock gutters for pinned panels.
  void applyDockGutters({
    int left = 0,
    int top = 0,
    int right = 0,
    int bottom = 0,
  }) {
    _dockLeft = left.clamp(0, terminal.columns - 1);
    _dockRight = right.clamp(0, terminal.columns - 1);
    _dockTop = top.clamp(0, terminal.rows - 1);
    _dockBottom = bottom.clamp(0, terminal.rows - 1);
    apply();
  }

  /// Update the overlay zone height. Call before rendering.
  ///
  /// Only calls [apply] if the height actually changed to avoid flicker.
  void setOverlayHeight(int lines) {
    final clamped =
        lines.clamp(0, terminal.rows ~/ AppConstants.inputAreaDivisor);
    if (clamped == _overlayHeight) return;
    _overlayHeight = clamped;
    apply();
  }

  // ── Zone rendering helpers ────────────────────────────────────────────

  /// Paint the output zone with pre-computed lines for scrollback.
  void paintOutputViewport(List<String> lines) {
    final height = outputHeight;
    for (var i = 0; i < height; i++) {
      terminal.moveTo(outputTop + i, 1);
      terminal.clearLine();
      if (i < lines.length) {
        terminal.moveTo(outputTop + i, outputLeft);
        final truncated = ansiTruncate(lines[i], outputWidth);
        terminal.write(truncated);
        final padding = outputWidth - visibleLength(truncated);
        if (padding > 0) terminal.write(' ' * padding);
      }
    }
  }

  /// Append [text] to the output zone (scrolls naturally within the
  /// scroll region).
  void writeOutput(String text) {
    terminal.saveCursor();
    terminal.moveTo(outputBottom, outputLeft);
    terminal.write('\n$text');
    terminal.restoreCursor();
  }

  /// Paint the overlay zone with pre-rendered lines.
  void paintOverlay(List<String> lines) {
    for (var i = 0; i < _overlayHeight; i++) {
      terminal.moveTo(overlayTop + i, 1);
      terminal.clearLine();
      if (i < lines.length) {
        terminal.moveTo(overlayTop + i, outputLeft);
        final truncated = ansiTruncate(lines[i], outputWidth);
        terminal.write(truncated);
        final padding = outputWidth - visibleLength(truncated);
        if (padding > 0) terminal.write(' ' * padding);
      } else {
        terminal.moveTo(overlayTop + i, outputLeft);
        terminal.write(' ' * outputWidth);
      }
    }
  }

  /// Paint a rectangular block without disturbing other cells.
  void paintRect({
    required int row,
    required int col,
    required int width,
    required int height,
    required List<String> lines,
  }) {
    if (width <= 0 || height <= 0) return;

    final clippedRow = row.clamp(1, terminal.rows);
    final clippedCol = col.clamp(1, terminal.columns);
    final maxHeight = terminal.rows - clippedRow + 1;
    final maxWidth = terminal.columns - clippedCol + 1;
    final safeHeight = height.clamp(0, maxHeight);
    final safeWidth = width.clamp(0, maxWidth);
    if (safeHeight <= 0 || safeWidth <= 0) return;

    for (var i = 0; i < safeHeight; i++) {
      terminal.moveTo(clippedRow + i, clippedCol);
      final raw = i < lines.length ? lines[i] : '';
      final truncated = ansiTruncate(raw, safeWidth);
      final padding = safeWidth - visibleLength(truncated);
      terminal.write(truncated);
      if (padding > 0) terminal.write(' ' * padding);
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
      style: const AnsiStyle('\x1b[30;43m', '\x1b[0m'),
    );
  }

  /// Paint the multiline input area.
  ///
  /// [prompt] is shown on the first line (e.g. '❯ '), continuation lines
  /// are indented with a dimmed '· ' indicator to the same width.
  /// [lines] are the logical lines of text, [cursorRow] and [cursorCol]
  /// are the cursor position within the logical lines.
  ///
  /// Handles visual line wrapping and scrolls the viewport when content
  /// exceeds [AppConstants.maxInputVisibleLines].
  void paintInput(
    String prompt,
    List<String> lines,
    int cursorRow,
    int cursorCol, {
    bool showCursor = true,
    AnsiStyle promptStyle = AnsiStyle.yellow,
  }) {
    final cols = terminal.columns;
    final promptWidth = visibleLength(prompt);

    // Build visual lines: each logical line may wrap into multiple
    // visual rows. Track which visual row the cursor lands on.
    final visualLines = <_VisualLine>[];
    var cursorVisualRow = 0;
    var cursorScreenCol = 1;

    for (var logRow = 0; logRow < lines.length; logRow++) {
      final line = lines[logRow];
      final prefixWidth = promptWidth; // indent continuation to same width
      final availWidth = (cols - prefixWidth).clamp(1, cols);

      // Compute visual width of each character for wrapping.
      final charWidths = <int>[];
      for (final cp in line.runes) {
        charWidths.add(charWidth(cp));
      }

      // Split into visual chunks based on available width.
      final runes = line.runes.toList();
      var charIdx = 0;
      var isFirstChunk = true;

      if (runes.isEmpty) {
        // Empty line — still gets one visual row.
        visualLines.add(_VisualLine(
          text: '',
          logicalRow: logRow,
          isFirstOfLogical: isFirstChunk,
        ));
        if (logRow == cursorRow && cursorCol == 0) {
          cursorVisualRow = visualLines.length - 1;
          cursorScreenCol = prefixWidth + 1;
        }
        isFirstChunk = false;
      } else {
        while (charIdx < runes.length) {
          final chunk = StringBuffer();
          var usedWidth = 0;
          final chunkStartIdx = charIdx;

          while (charIdx < runes.length) {
            final w = charWidths[charIdx];
            if (usedWidth + w > availWidth) break;
            chunk.writeCharCode(runes[charIdx]);
            usedWidth += w;
            charIdx++;
          }

          // If no progress (character wider than available), force one char.
          if (chunk.isEmpty && charIdx < runes.length) {
            chunk.writeCharCode(runes[charIdx]);
            charIdx++;
          }

          visualLines.add(_VisualLine(
            text: chunk.toString(),
            logicalRow: logRow,
            isFirstOfLogical: isFirstChunk,
          ));

          // Track cursor position: cursor is in this chunk when its
          // column falls within [chunkStartIdx, charIdx) — or at charIdx
          // if this is the last chunk of the line.
          if (logRow == cursorRow &&
              cursorCol >= chunkStartIdx &&
              (cursorCol < charIdx || charIdx == runes.length)) {
            var colWidth = 0;
            for (var c = chunkStartIdx; c < cursorCol; c++) {
              colWidth += charWidths[c];
            }
            cursorVisualRow = visualLines.length - 1;
            cursorScreenCol = prefixWidth + colWidth + 1;
          }

          isFirstChunk = false;
        }
      }
    }

    // Scrolling: keep cursor visible within the viewport.
    const maxVisible = AppConstants.maxInputVisibleLines;
    final totalVisual = visualLines.length;
    var scrollOffset = _inputScrollOffset;

    if (totalVisual <= maxVisible) {
      scrollOffset = 0;
    } else {
      // Ensure cursor row is visible.
      if (cursorVisualRow < scrollOffset) {
        scrollOffset = cursorVisualRow;
      } else if (cursorVisualRow >= scrollOffset + maxVisible) {
        scrollOffset = cursorVisualRow - maxVisible + 1;
      }
    }
    _inputScrollOffset = scrollOffset;

    final visibleCount = totalVisual <= maxVisible ? totalVisual : maxVisible;

    // Update the input height in the layout.
    setInputHeight(visibleCount);

    // Paint each visible visual line.
    for (var vi = 0; vi < visibleCount; vi++) {
      final vLine = visualLines[scrollOffset + vi];
      final screenRow = inputTop + vi;
      terminal.moveTo(screenRow, 1);
      terminal.clearLine();

      if (vLine.isFirstOfLogical && vLine.logicalRow == 0) {
        // First line gets the prompt.
        terminal.writeStyled(prompt, style: promptStyle);
      } else if (vLine.isFirstOfLogical) {
        // Continuation logical lines get a dimmed indicator.
        final indicator = '· '.padLeft(promptWidth);
        terminal.writeStyled(indicator, style: AnsiStyle.dim);
      } else {
        // Wrapped visual lines get blank indent.
        terminal.write(' ' * promptWidth);
      }

      terminal.write(vLine.text);

      // Clear rest of line.
      final usedCols = promptWidth + visibleLength(vLine.text);
      if (usedCols < cols) {
        terminal.write(' ' * (cols - usedCols));
      }
    }

    // Position cursor.
    if (showCursor &&
        cursorVisualRow >= scrollOffset &&
        cursorVisualRow < scrollOffset + visibleCount) {
      final screenRow = inputTop + (cursorVisualRow - scrollOffset);
      terminal.moveTo(screenRow, cursorScreenCol.clamp(1, cols));
      terminal.showCursor();
    }
  }

  int _inputScrollOffset = 0;
}

/// A single visual (screen) row of the input area.
class _VisualLine {
  final String text;
  final int logicalRow;
  final bool isFirstOfLogical;

  _VisualLine({
    required this.text,
    required this.logicalRow,
    required this.isFirstOfLogical,
  });
}
