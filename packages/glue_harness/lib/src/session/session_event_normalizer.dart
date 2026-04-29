enum NormalizedSessionEventKind { user, assistant, toolCall, toolResult }

class NormalizedSessionEvent {
  final NormalizedSessionEventKind kind;
  final String text;
  final String? toolCallId;
  final String? toolName;
  final Map<String, dynamic>? toolArguments;
  final String? toolResultSummary;

  const NormalizedSessionEvent._({
    required this.kind,
    required this.text,
    this.toolCallId,
    this.toolName,
    this.toolArguments,
    this.toolResultSummary,
  });

  factory NormalizedSessionEvent.user(String text) => NormalizedSessionEvent._(
      kind: NormalizedSessionEventKind.user, text: text);

  factory NormalizedSessionEvent.assistant(String text) =>
      NormalizedSessionEvent._(
        kind: NormalizedSessionEventKind.assistant,
        text: text,
      );

  factory NormalizedSessionEvent.toolCall({
    String? id,
    required String name,
    required Map<String, dynamic> arguments,
  }) =>
      NormalizedSessionEvent._(
        kind: NormalizedSessionEventKind.toolCall,
        text: name,
        toolCallId: id,
        toolName: name,
        toolArguments: arguments,
      );

  factory NormalizedSessionEvent.toolResult({
    String? callId,
    required String content,
    String? summary,
  }) =>
      NormalizedSessionEvent._(
        kind: NormalizedSessionEventKind.toolResult,
        text: content,
        toolCallId: callId,
        toolResultSummary: summary,
      );

  String get visibleText {
    if (kind != NormalizedSessionEventKind.toolResult) {
      return text;
    }
    final summary = toolResultSummary?.trim();
    return (summary != null && summary.isNotEmpty) ? summary : text;
  }
}

Iterable<NormalizedSessionEvent> normalizeSessionEvents(
  List<Map<String, dynamic>> events,
) sync* {
  for (final event in events) {
    final normalized = normalizeSessionEvent(event);
    if (normalized != null) yield normalized;
  }
}

NormalizedSessionEvent? normalizeSessionEvent(Map<String, dynamic> event) {
  final type = event['type'] as String?;
  switch (type) {
    case 'user_message':
      final text = event['text'] as String? ?? '';
      if (text.isEmpty) return null;
      return NormalizedSessionEvent.user(text);
    case 'assistant_message':
      final text = event['text'] as String? ?? '';
      if (text.isEmpty) return null;
      return NormalizedSessionEvent.assistant(text);
    case 'tool_call':
      final name = (event['name'] as String? ?? '').trim();
      if (name.isEmpty) return null;
      return NormalizedSessionEvent.toolCall(
        id: event['id'] as String?,
        name: name,
        arguments: _normalizeArguments(event['arguments']),
      );
    case 'tool_result':
      final summary = event['summary'] as String?;
      final content = event['content'] as String? ?? '';
      final visibleText = _visibleToolResultText(content, summary);
      if (visibleText.isEmpty) return null;
      return NormalizedSessionEvent.toolResult(
        callId: event['call_id'] as String?,
        content: content,
        summary: summary,
      );
    default:
      return null;
  }
}

Map<String, dynamic> _normalizeArguments(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return raw.map((key, value) => MapEntry('$key', value));
  }
  return const <String, dynamic>{};
}

String _visibleToolResultText(String content, String? summary) {
  final normalizedSummary = summary?.trim();
  if (normalizedSummary != null && normalizedSummary.isNotEmpty) {
    return normalizedSummary;
  }
  return content;
}
