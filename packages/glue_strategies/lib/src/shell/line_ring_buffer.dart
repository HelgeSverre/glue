import 'dart:collection';

/// A ring buffer that keeps the most recent lines of output, bounded by
/// both line count and total byte size.
///
/// Used to capture process output without unbounded memory growth — for
/// example, a background job that runs for hours will only keep its last
/// [maxLines] lines. Partial lines (text without a trailing newline) are
/// held in an internal buffer until the next [addText] call completes them.
class LineRingBuffer {
  final int maxLines;
  final int maxBytes;

  final _lines = ListQueue<String>();
  int _bytes = 0;
  String _partial = '';

  LineRingBuffer({required this.maxLines, required this.maxBytes});

  /// The number of lines currently held, including any buffered partial line.
  int get lineCount => _lines.length + (_partial.isNotEmpty ? 1 : 0);

  /// Appends raw text to the buffer, splitting it into lines on `\n`.
  ///
  /// If [text] doesn't end with a newline, the trailing fragment is held
  /// internally and prepended to the next [addText] call. This means you
  /// can safely feed in arbitrary chunks from a process stream.
  void addText(String text) {
    if (text.isEmpty) return;
    final parts = text.split('\n');
    if (parts.length == 1) {
      _partial += parts[0];
      return;
    }
    _commitLine(_partial + parts[0]);
    for (var i = 1; i < parts.length - 1; i++) {
      _commitLine(parts[i]);
    }
    _partial = parts.last;
  }

  void _commitLine(String line) {
    final b = line.length + 1;
    _lines.add(line);
    _bytes += b;
    while (_lines.length > maxLines || _bytes > maxBytes) {
      if (_lines.isEmpty) break;
      final removed = _lines.removeFirst();
      _bytes -= removed.length + 1;
    }
  }

  String tail({int lines = 200}) {
    final all = _allLines().toList();
    final start = (all.length - lines).clamp(0, all.length);
    return all.sublist(start).join('\n');
  }

  String dump() => _allLines().join('\n');

  Iterable<String> _allLines() sync* {
    yield* _lines;
    if (_partial.isNotEmpty) yield _partial;
  }
}
