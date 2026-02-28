import 'dart:collection';

/// Circular buffer capped by line count and byte size.
///
/// Partial lines (text without a trailing newline) are buffered until
/// the next call to [addText]. Oldest lines are evicted first.
class LineRingBuffer {
  final int maxLines;
  final int maxBytes;

  final _lines = ListQueue<String>();
  int _bytes = 0;
  String _partial = '';

  LineRingBuffer({required this.maxLines, required this.maxBytes});

  /// Includes any buffered partial line in the count.
  int get lineCount => _lines.length + (_partial.isNotEmpty ? 1 : 0);

  /// Splits on newlines; a trailing incomplete line is buffered until the next call.
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
