import 'dart:async';
import 'dart:convert';

/// A single Server-Sent Event.
class SseEvent {
  final String? event;
  final String data;
  SseEvent({this.event, required this.data});

  @override
  String toString() => 'SseEvent(event: $event, data: $data)';
}

/// Decode a raw byte stream (from an HTTP response) into [SseEvent]s.
///
/// Follows the SSE specification:
/// - Events are separated by blank lines.
/// - Lines starting with `:` are comments (ignored).
/// - `data: [DONE]` is treated as end-of-stream (OpenAI convention).
/// - Multiple `data:` lines in one event are joined with newlines.
Stream<SseEvent> decodeSse(Stream<List<int>> bytes) async* {
  String? currentEvent;
  final dataLines = <String>[];
  final buffer = StringBuffer();

  // Use utf8.decoder (a StreamTransformer) instead of utf8.decode() to
  // correctly handle multi-byte characters split across chunk boundaries.
  await for (final str in bytes.cast<List<int>>().transform(utf8.decoder)) {
    buffer.write(str);

    while (true) {
      final content = buffer.toString();
      final nlIndex = content.indexOf('\n');
      if (nlIndex == -1) break;

      final line = content.substring(0, nlIndex);
      // Remove the consumed line (including the \n).
      buffer
        ..clear()
        ..write(content.substring(nlIndex + 1));

      // Strip trailing \r for CRLF compatibility.
      final trimmed =
          line.endsWith('\r') ? line.substring(0, line.length - 1) : line;

      if (trimmed.isEmpty) {
        // Blank line = event boundary.
        if (dataLines.isNotEmpty) {
          final joined = dataLines.join('\n');
          if (joined == '[DONE]') {
            // OpenAI end sentinel — stop.
            return;
          }
          yield SseEvent(event: currentEvent, data: joined);
        }
        currentEvent = null;
        dataLines.clear();
        continue;
      }

      // Comment line.
      if (trimmed.startsWith(':')) continue;

      // Field parsing.
      final colonIndex = trimmed.indexOf(':');
      if (colonIndex == -1) continue;

      final field = trimmed.substring(0, colonIndex);
      // Value starts after `: ` (space is optional per spec).
      var value = trimmed.substring(colonIndex + 1);
      if (value.startsWith(' ')) value = value.substring(1);

      switch (field) {
        case 'event':
          currentEvent = value;
        case 'data':
          dataLines.add(value);
      }
    }
  }

  // Flush any remaining event (no trailing blank line).
  if (dataLines.isNotEmpty) {
    final joined = dataLines.join('\n');
    if (joined != '[DONE]') {
      yield SseEvent(event: currentEvent, data: joined);
    }
  }
}
