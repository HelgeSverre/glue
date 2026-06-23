import 'dart:async';
import 'dart:convert';

/// Decode a newline-delimited JSON stream (NDJSON) from raw bytes.
///
/// Ollama uses this format instead of SSE: each line is a complete
/// JSON object, streamed one per response chunk.
///
/// Bytes are decoded with `utf8.decoder` (handling multi-byte characters
/// split across chunk boundaries) and split into lines with [LineSplitter],
/// which buffers partial trailing lines until their newline arrives.
Stream<Map<String, dynamic>> decodeNdjson(Stream<List<int>> bytes) async* {
  final lines = bytes
      .cast<List<int>>()
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  await for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    yield jsonDecode(trimmed) as Map<String, dynamic>;
  }
}
