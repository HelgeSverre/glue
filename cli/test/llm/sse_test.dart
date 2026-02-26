import 'dart:async';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:glue/src/llm/sse.dart';

void main() {
  group('SseDecoder', () {
    test('parses simple data-only events', () async {
      final input = 'data: {"text":"hello"}\n\ndata: {"text":"world"}\n\n';
      final stream = Stream.value(utf8.encode(input));
      final events = await decodeSse(stream).toList();

      expect(events, hasLength(2));
      expect(events[0].data, '{"text":"hello"}');
      expect(events[1].data, '{"text":"world"}');
    });

    test('parses events with event type', () async {
      final input = 'event: message_start\ndata: {"type":"message_start"}\n\n';
      final stream = Stream.value(utf8.encode(input));
      final events = await decodeSse(stream).toList();

      expect(events, hasLength(1));
      expect(events[0].event, 'message_start');
      expect(events[0].data, '{"type":"message_start"}');
    });

    test('ignores comment lines', () async {
      final input = ': ping\ndata: {"ok":true}\n\n';
      final stream = Stream.value(utf8.encode(input));
      final events = await decodeSse(stream).toList();

      expect(events, hasLength(1));
      expect(events[0].data, '{"ok":true}');
    });

    test('handles data: [DONE] sentinel', () async {
      final input = 'data: {"text":"hi"}\n\ndata: [DONE]\n\n';
      final stream = Stream.value(utf8.encode(input));
      final events = await decodeSse(stream).toList();

      expect(events, hasLength(1));
      expect(events[0].data, '{"text":"hi"}');
    });

    test('handles multi-line data fields', () async {
      final input = 'data: line1\ndata: line2\n\n';
      final stream = Stream.value(utf8.encode(input));
      final events = await decodeSse(stream).toList();

      expect(events, hasLength(1));
      expect(events[0].data, 'line1\nline2');
    });

    test('handles chunked byte delivery', () async {
      final full = 'data: {"x":1}\n\ndata: {"x":2}\n\n';
      final bytes = utf8.encode(full);
      // Split into small chunks to simulate real network
      final chunks = <List<int>>[];
      for (var i = 0; i < bytes.length; i += 5) {
        chunks.add(bytes.sublist(i, (i + 5).clamp(0, bytes.length)));
      }
      final stream = Stream.fromIterable(chunks);
      final events = await decodeSse(stream).toList();

      expect(events, hasLength(2));
    });
  });
}
