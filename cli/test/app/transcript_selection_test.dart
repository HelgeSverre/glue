import 'package:glue/glue.dart';
import 'package:test/test.dart';

void main() {
  group('classify', () {
    test('whitespace, punctuation, and word chars are distinguished', () {
      expect(classify(0x20), CharClass.whitespace); // space
      expect(classify(0x09), CharClass.whitespace); // tab
      expect(classify(0xA0), CharClass.whitespace); // NBSP
      expect(classify(0x2E), CharClass.punctuation); // .
      expect(classify(0x28), CharClass.punctuation); // (
      expect(classify(0x40), CharClass.punctuation); // @
      expect(classify(0x61), CharClass.word); // a
      expect(classify(0x5F), CharClass.word); // _
      expect(classify(0x30), CharClass.word); // 0
      expect(classify(0x4E2D), CharClass.word); // 中
      expect(classify(0x1F600), CharClass.word); // 😀
      expect(classify(0x0301), CharClass.word); // combining acute
    });

    test('every punctuation char in the explicit set is punctuation', () {
      const set =
          r'/:,.-(){}[];"'
          "'"
          r'<>=+*&|!@#$%^~`\?';
      for (final cu in set.codeUnits) {
        expect(
          classify(cu),
          CharClass.punctuation,
          reason: 'expected punctuation for U+${cu.toRadixString(16)}',
        );
      }
    });
  });

  group('findClassRange', () {
    test('selects an identifier run including underscores', () {
      // "foo_bar baz" — clicking inside foo_bar selects exactly foo_bar.
      expect(findClassRange('foo_bar baz', 4), equals((0, 7)));
      expect(findClassRange('foo_bar baz', 0), equals((0, 7)));
      expect(findClassRange('foo_bar baz', 6), equals((0, 7)));
    });

    test('selects just a single punctuation char between identifiers', () {
      // "foo.bar" — clicking the dot selects only the dot.
      expect(findClassRange('foo.bar', 3), equals((3, 4)));
    });

    test('selects a contiguous punctuation run', () {
      // All three chars are punctuation → the full run is selected.
      expect(findClassRange('(()', 0), equals((0, 3)));
      expect(findClassRange('(()', 1), equals((0, 3)));
      // Mixed: punctuation between identifiers — only the punct run.
      expect(findClassRange('foo((bar', 3), equals((3, 5)));
    });

    test('selects a whitespace run when clicking on whitespace', () {
      expect(findClassRange('   ', 1), equals((0, 3)));
    });

    test('empty string returns empty range', () {
      expect(findClassRange('', 0), equals((0, 0)));
    });

    test('out-of-range offsets clamp into a valid range', () {
      expect(findClassRange('hi', 99), equals((0, 2)));
      expect(findClassRange('hi', -5), equals((0, 2)));
    });

    test('CJK identifiers select as a single word', () {
      expect(findClassRange('漢字', 0), equals((0, 2)));
    });

    test('surrogate-pair emoji stays atomic in a word run', () {
      // "😀😀" is two 4-byte glyphs = 4 UTF-16 code units, all word class.
      // Clicking anywhere inside should select both glyphs.
      expect(findClassRange('😀😀', 0), equals((0, 4)));
      expect(findClassRange('😀😀', 2), equals((0, 4)));
    });
  });

  group('ClickChain', () {
    test('counts go 1 -> 2 -> 3 at the same cell within the window', () {
      final chain = ClickChain();
      final t = DateTime(2026, 5, 19, 12);
      expect(chain.register(10, 5, t), 1);
      expect(chain.register(10, 5, t.add(const Duration(milliseconds: 50))), 2);
      expect(
        chain.register(10, 5, t.add(const Duration(milliseconds: 100))),
        3,
      );
    });

    test('a fourth click in-window wraps back to 1', () {
      final chain = ClickChain();
      final t = DateTime(2026, 5, 19, 12);
      chain.register(10, 5, t);
      chain.register(10, 5, t.add(const Duration(milliseconds: 50)));
      chain.register(10, 5, t.add(const Duration(milliseconds: 100)));
      expect(
        chain.register(10, 5, t.add(const Duration(milliseconds: 150))),
        1,
      );
    });

    test('a slow click outside the window resets the chain', () {
      final chain = ClickChain();
      final t = DateTime(2026, 5, 19, 12);
      chain.register(10, 5, t);
      // 301 ms is just past the 300 ms window.
      expect(
        chain.register(10, 5, t.add(const Duration(milliseconds: 301))),
        1,
      );
    });

    test('a click at an adjacent cell resets the chain', () {
      final chain = ClickChain();
      final t = DateTime(2026, 5, 19, 12);
      chain.register(10, 5, t);
      // Even a 1-cell wobble is treated as a fresh click — terminals
      // report integer cells so true double-clicks land on the same cell.
      expect(chain.register(11, 5, t.add(const Duration(milliseconds: 50))), 1);
      expect(
        chain.register(10, 6, t.add(const Duration(milliseconds: 100))),
        1,
      );
    });

    test('reset() zeroes the count and timestamp', () {
      final chain = ClickChain();
      final t = DateTime(2026, 5, 19, 12);
      chain.register(10, 5, t);
      chain.register(10, 5, t.add(const Duration(milliseconds: 50)));
      chain.reset();
      expect(chain.count, 0);
      // After reset, the next click is a fresh 1 regardless of timing.
      expect(chain.register(10, 5, t.add(const Duration(milliseconds: 60))), 1);
    });
  });

  group('TranscriptSelection.ordered', () {
    test('returns null when a block id is missing from the order list', () {
      const sel = TranscriptSelection(
        anchor: TranscriptPosition(blockId: 'a', plainTextOffset: 0),
        focus: TranscriptPosition(blockId: 'z', plainTextOffset: 5),
      );
      expect(sel.ordered(const ['a', 'b']), isNull);
    });

    test('orders by block position when blocks differ', () {
      const sel = TranscriptSelection(
        anchor: TranscriptPosition(blockId: 'b', plainTextOffset: 0),
        focus: TranscriptPosition(blockId: 'a', plainTextOffset: 10),
      );
      final ordered = sel.ordered(const ['a', 'b'])!;
      expect(ordered.$1.blockId, 'a');
      expect(ordered.$2.blockId, 'b');
    });

    test('orders by offset within a single block', () {
      const sel = TranscriptSelection(
        anchor: TranscriptPosition(blockId: 'a', plainTextOffset: 7),
        focus: TranscriptPosition(blockId: 'a', plainTextOffset: 3),
      );
      final ordered = sel.ordered(const ['a'])!;
      expect(ordered.$1.plainTextOffset, 3);
      expect(ordered.$2.plainTextOffset, 7);
    });
  });

  group('TranscriptSelection.rebindBlockId', () {
    test('migrates streaming-sentinel anchors onto a finalized block', () {
      const sel = TranscriptSelection(
        anchor: TranscriptPosition(
          blockId: kStreamingAssistantId,
          plainTextOffset: 2,
        ),
        focus: TranscriptPosition(
          blockId: kStreamingAssistantId,
          plainTextOffset: 12,
        ),
      );
      final rebound = sel.rebindBlockId(kStreamingAssistantId, 'e42');
      expect(rebound.anchor.blockId, 'e42');
      expect(rebound.focus.blockId, 'e42');
      expect(rebound.anchor.plainTextOffset, 2);
      expect(rebound.focus.plainTextOffset, 12);
    });

    test('leaves unrelated block ids untouched', () {
      const sel = TranscriptSelection(
        anchor: TranscriptPosition(blockId: 'a', plainTextOffset: 0),
        focus: TranscriptPosition(blockId: 'a', plainTextOffset: 1),
      );
      expect(identical(sel.rebindBlockId('x', 'y'), sel), isTrue);
    });
  });

  group('DragState.observeMotion', () {
    test('flags the moment the cursor crosses the drag threshold', () {
      const origin = TranscriptPosition(blockId: 'a', plainTextOffset: 0);
      final drag = DragState(originX: 10, originY: 5, origin: origin);
      // Single-cell wobble still counts as a click.
      expect(drag.observeMotion(10, 6), isFalse);
      expect(drag.exceededThreshold, isFalse);
      // Crossing the 2-cell Manhattan distance threshold promotes to a drag.
      expect(drag.observeMotion(12, 5), isTrue);
      expect(drag.exceededThreshold, isTrue);
      // Subsequent calls return false (already promoted).
      expect(drag.observeMotion(20, 20), isFalse);
    });

    test('threshold is configurable via dragThresholdCells constant', () {
      // Document the constant exists and is what we expect — tests below
      // rely on `>= 2` Manhattan distance promoting to a drag.
      expect(dragThresholdCells, 2);
    });
  });
}
