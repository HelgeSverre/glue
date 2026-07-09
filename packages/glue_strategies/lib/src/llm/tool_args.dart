import 'dart:convert';

/// Accumulates a streamed tool call's id, name, and partial argument JSON,
/// then finalises it into a [ToolCall]-ready arguments map.
///
/// Both the Anthropic (`input_json_delta`) and OpenAI
/// (`delta.tool_calls[].function.arguments`) streaming shapes deliver tool
/// arguments as incremental JSON fragments that must be concatenated and
/// parsed once the block/stream finishes. When the concatenated buffer is
/// empty the result is an empty map; when it is non-empty but not valid JSON
/// (a provider quirk seen in practice) the raw text is preserved under a
/// single `_raw` key rather than dropped.
class ToolArgsBuffer<Id> {
  ToolArgsBuffer({required this.id, required this.name});

  final Id id;
  final String name;
  final StringBuffer _buffer = StringBuffer();

  /// Append a partial-JSON fragment for this tool call.
  void write(String fragment) => _buffer.write(fragment);

  /// Parse the accumulated buffer into an arguments map.
  ///
  /// Empty buffer → `{}`. A JSON object → itself. Anything else — invalid
  /// JSON, or valid-but-non-object JSON (`"foo"`, `[1,2]`, `42`) — falls back
  /// to `{'_raw': <buffer>}`. The non-object case previously slipped past the
  /// `FormatException` catch and threw a `TypeError` on the `as Map` cast
  /// (L16).
  Map<String, dynamic> finalizeArguments() {
    final raw = _buffer.toString();
    if (raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', value));
      }
      return <String, dynamic>{'_raw': raw};
    } on FormatException {
      return <String, dynamic>{'_raw': raw};
    }
  }
}
