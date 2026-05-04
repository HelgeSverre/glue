enum NormalizedSessionEventKind {
  user,
  assistant,
  toolCall,
  toolResult,
  subagentSpawned,
  subagentEvent,
  subagentCompleted,
}

class NormalizedSessionEvent {
  final NormalizedSessionEventKind kind;
  final String text;
  final String? toolCallId;
  final String? toolName;
  final Map<String, dynamic>? toolArguments;
  final String? toolResultSummary;

  // Subagent-specific fields. Populated on subagent* kinds; null otherwise.
  final String? subagentId;
  final int? subagentIndex;
  final int? subagentTotal;
  final int? subagentDepth;
  final NormalizedSessionEvent? subagentInner;
  final String? subagentError;

  const NormalizedSessionEvent._({
    required this.kind,
    required this.text,
    this.toolCallId,
    this.toolName,
    this.toolArguments,
    this.toolResultSummary,
    this.subagentId,
    this.subagentIndex,
    this.subagentTotal,
    this.subagentDepth,
    this.subagentInner,
    this.subagentError,
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

  factory NormalizedSessionEvent.subagentSpawned({
    required String subagentId,
    required String task,
    int? index,
    int? total,
    int? depth,
  }) =>
      NormalizedSessionEvent._(
        kind: NormalizedSessionEventKind.subagentSpawned,
        text: task,
        subagentId: subagentId,
        subagentIndex: index,
        subagentTotal: total,
        subagentDepth: depth,
      );

  factory NormalizedSessionEvent.subagentEvent({
    required String subagentId,
    required NormalizedSessionEvent inner,
  }) =>
      NormalizedSessionEvent._(
        kind: NormalizedSessionEventKind.subagentEvent,
        text: inner.visibleText,
        subagentId: subagentId,
        subagentInner: inner,
      );

  factory NormalizedSessionEvent.subagentCompleted({
    required String subagentId,
    String? error,
  }) =>
      NormalizedSessionEvent._(
        kind: NormalizedSessionEventKind.subagentCompleted,
        text: error ?? '',
        subagentId: subagentId,
        subagentError: error,
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
    case 'subagent_spawned':
      final id = (event['subagent_id'] as String? ?? '').trim();
      final task = (event['task'] as String? ?? '').trim();
      if (id.isEmpty || task.isEmpty) return null;
      return NormalizedSessionEvent.subagentSpawned(
        subagentId: id,
        task: task,
        index: event['index'] as int?,
        total: event['total'] as int?,
        depth: event['depth'] as int?,
      );
    case 'subagent_event':
      final id = (event['subagent_id'] as String? ?? '').trim();
      if (id.isEmpty) return null;
      final inner = event['inner'];
      if (inner is! Map) return null;
      final innerMap = inner is Map<String, dynamic>
          ? inner
          : inner.map((k, v) => MapEntry('$k', v));
      final normalizedInner = normalizeSessionEvent(innerMap);
      if (normalizedInner == null) return null;
      return NormalizedSessionEvent.subagentEvent(
        subagentId: id,
        inner: normalizedInner,
      );
    case 'subagent_completed':
      final id = (event['subagent_id'] as String? ?? '').trim();
      if (id.isEmpty) return null;
      return NormalizedSessionEvent.subagentCompleted(
        subagentId: id,
        error: event['error'] as String?,
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
