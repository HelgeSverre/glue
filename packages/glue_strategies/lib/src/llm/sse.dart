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
///
/// Byte buffering is delegated to `utf8.decoder` + [LineSplitter] (which
/// handles multi-byte characters and CRLF split across chunk boundaries);
/// this function holds only the SSE field state machine over whole lines.
Stream<SseEvent> decodeSse(Stream<List<int>> bytes) async* {
  String? currentEvent;
  final dataLines = <String>[];

  final lines = bytes
      .cast<List<int>>()
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  await for (final line in lines) {
    if (line.isEmpty) {
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
    if (line.startsWith(':')) continue;

    // Field parsing.
    final colonIndex = line.indexOf(':');
    if (colonIndex == -1) continue;

    final field = line.substring(0, colonIndex);
    // Value starts after `: ` (space is optional per spec).
    var value = line.substring(colonIndex + 1);
    if (value.startsWith(' ')) value = value.substring(1);

    switch (field) {
      case 'event':
        currentEvent = value;
      case 'data':
        dataLines.add(value);
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
