import 'dart:async';
import 'dart:convert';

/// Decode a newline-delimited JSON stream (NDJSON) from raw bytes.
///
/// Ollama uses this format instead of SSE: each line is a complete
/// JSON object, streamed one per response chunk.
Stream<Map<String, dynamic>> decodeNdjson(Stream<List<int>> bytes) async* {
  final buffer = StringBuffer();

  await for (final chunk in bytes) {
    buffer.write(utf8.decode(chunk));

    while (true) {
      final content = buffer.toString();
      final nlIndex = content.indexOf('\n');
      if (nlIndex == -1) break;

      final line = content.substring(0, nlIndex).trim();
      buffer
        ..clear()
        ..write(content.substring(nlIndex + 1));

      if (line.isEmpty) continue;

      yield jsonDecode(line) as Map<String, dynamic>;
    }
  }

  // Flush remaining content.
  final remaining = buffer.toString().trim();
  if (remaining.isNotEmpty) {
    yield jsonDecode(remaining) as Map<String, dynamic>;
  }
}
