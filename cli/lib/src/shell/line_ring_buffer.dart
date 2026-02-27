import 'dart:collection';

class LineRingBuffer {
  final int maxLines;
  final int maxBytes;
  final _lines = ListQueue<String>();
  int _bytes = 0;

  LineRingBuffer({required this.maxLines, required this.maxBytes});

  int get lineCount => _lines.length;

  void addText(String text) {
    for (final line in text.split('\n')) {
      _pushLine(line);
    }
  }

  void _pushLine(String line) {
    final b = line.length + 1;
    _lines.add(line);
    _bytes += b;
    while (_lines.length > maxLines || _bytes > maxBytes) {
      if (_lines.isEmpty) break;
      final removed = _lines.removeFirst();
      _bytes -= (removed.length + 1);
    }
  }

  String tail({int lines = 200}) {
    final start = (_lines.length - lines).clamp(0, _lines.length);
    return _lines.skip(start).join('\n');
  }

  String dump() => _lines.join('\n');
}
