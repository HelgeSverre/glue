import 'package:test/test.dart';
import 'package:glue/src/shell/line_ring_buffer.dart';

void main() {
  group('LineRingBuffer', () {
    test('stores and retrieves added lines', () {
      final buf = LineRingBuffer(maxLines: 100, maxBytes: 10000);
      buf.addText('line one\nline two\nline three');
      expect(buf.dump(), equals('line one\nline two\nline three'));
    });

    test('tail returns last N lines', () {
      final buf = LineRingBuffer(maxLines: 100, maxBytes: 10000);
      for (var i = 0; i < 10; i++) {
        buf.addText('line $i\n');
      }
      final tail = buf.tail(lines: 3);
      expect(tail, contains('line 7'));
      expect(tail, contains('line 8'));
      expect(tail, contains('line 9'));
      expect(tail, isNot(contains('line 6')));
    });

    test('evicts oldest lines when maxLines exceeded', () {
      final buf = LineRingBuffer(maxLines: 5, maxBytes: 100000);
      for (var i = 0; i < 10; i++) {
        buf.addText('line $i\n');
      }
      final dump = buf.dump();
      expect(dump, isNot(contains('line 0')));
      expect(dump, isNot(contains('line 4')));
      expect(dump, contains('line 5'));
      expect(dump, contains('line 9'));
    });

    test('evicts oldest lines when maxBytes exceeded', () {
      final buf = LineRingBuffer(maxLines: 10000, maxBytes: 30);
      buf.addText('aaaaaaaaaa\n'); // 11 bytes
      buf.addText('bbbbbbbbbb\n'); // 11 bytes
      buf.addText('cccccccccc\n'); // 11 bytes -> exceeds 30, evict oldest
      final dump = buf.dump();
      expect(dump, isNot(contains('aaa')));
      expect(dump, contains('bbb'));
      expect(dump, contains('ccc'));
    });

    test('lineCount tracks stored lines', () {
      final buf = LineRingBuffer(maxLines: 100, maxBytes: 10000);
      buf.addText('a\nb\nc');
      expect(buf.lineCount, equals(3));
    });

    test('handles empty input', () {
      final buf = LineRingBuffer(maxLines: 100, maxBytes: 10000);
      buf.addText('');
      expect(buf.dump(), equals(''));
    });

    test('handles multiple addText calls building partial lines', () {
      final buf = LineRingBuffer(maxLines: 100, maxBytes: 10000);
      buf.addText('hello ');
      buf.addText('world\nfoo');
      final dump = buf.dump();
      expect(dump, contains('hello world'));
      expect(dump, contains('foo'));
    });
  });
}
