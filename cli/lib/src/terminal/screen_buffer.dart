import 'package:glue/src/terminal/terminal.dart';

/// A single cell in the virtual terminal grid.
class Cell {
  String char;
  AnsiStyle? style;

  Cell(this.char, {this.style});

  @override
  bool operator ==(Object other) =>
      other is Cell && other.char == char && other.style == style;

  @override
  int get hashCode => Object.hash(char, style);
}

/// Virtual terminal buffer with diff-based rendering.
///
/// Maintains a double-buffered grid of [Cell]s. On each [flush], only cells
/// that differ from the previous frame are written to the real terminal,
/// eliminating flicker.
class ScreenBuffer {
  final Terminal _terminal;
  late List<List<Cell>> _current;
  late List<List<Cell>> _previous;
  int _width;
  int _height;

  ScreenBuffer(this._terminal)
      : _width = _terminal.columns,
        _height = _terminal.rows {
    _current = _makeGrid(_width, _height);
    _previous = _makeGrid(_width, _height);
  }

  /// Current buffer width.
  int get width => _width;

  /// Current buffer height.
  int get height => _height;

  List<List<Cell>> _makeGrid(int w, int h) =>
      List.generate(h, (_) => List.generate(w, (_) => Cell(' ')));

  /// Write [text] into the buffer at ([row], [col]) without touching the
  /// real terminal. An optional [style] is applied to every character.
  void writeAt(int row, int col, String text, {AnsiStyle? style}) {
    if (row < 0 || row >= _height) return;
    final chars = text.runes.toList();
    for (var i = 0; i < chars.length && col + i < _width; i++) {
      if (col + i < 0) continue;
      _current[row][col + i] =
          Cell(String.fromCharCode(chars[i]), style: style);
    }
  }

  /// Fill an entire [row] starting at [startCol] with [text], padding with
  /// spaces to the right edge.
  void fillRow(int row, String text, {AnsiStyle? style, int startCol = 0}) {
    writeAt(row, startCol, text.padRight(_width - startCol), style: style);
  }

  /// Clear the current buffer (fill with spaces).
  void clear() {
    for (var r = 0; r < _height; r++) {
      for (var c = 0; c < _width; c++) {
        _current[r][c] = Cell(' ');
      }
    }
  }

  /// Flush only changed cells to the real terminal.
  ///
  /// This is the key to flicker-free rendering: we compare each cell against
  /// the previous frame and only emit ANSI sequences for cells that differ.
  void flush() {
    _terminal.hideCursor();
    final buf = StringBuffer();

    for (var r = 0; r < _height; r++) {
      for (var c = 0; c < _width; c++) {
        if (_current[r][c] != _previous[r][c]) {
          buf.write('\x1b[${r + 1};${c + 1}H');
          final cell = _current[r][c];
          if (cell.style != null) {
            buf.write('${cell.style!.open}${cell.char}${cell.style!.close}');
          } else {
            buf.write(cell.char);
          }
        }
      }
    }

    if (buf.isNotEmpty) {
      _terminal.write(buf.toString());
    }

    _terminal.showCursor();

    // Swap buffers: previous becomes current, current is cleared for the
    // next frame.
    final temp = _previous;
    _previous = _current;
    _current = temp;
    for (var r = 0; r < _height; r++) {
      for (var c = 0; c < _width; c++) {
        _current[r][c] = Cell(' ');
      }
    }
  }

  /// Handle a terminal resize.
  void resize(int width, int height) {
    _width = width;
    _height = height;
    _current = _makeGrid(width, height);
    _previous = _makeGrid(width, height);
  }
}
