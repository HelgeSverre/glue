enum ShareEntryKind {
  user,
  assistant,
  toolCall,
  toolResult,
  subagentGroup,
  subagentMessage,
}

class ShareEntry {
  final int index;
  final ShareEntryKind kind;
  final String text;
  final String? toolName;
  final Map<String, dynamic>? toolArguments;
  final String? subagentId;
  final int nestingLevel;
  final List<ShareEntry> children;

  const ShareEntry({
    required this.index,
    required this.kind,
    required this.text,
    this.toolName,
    this.toolArguments,
    this.subagentId,
    this.nestingLevel = 0,
    this.children = const [],
  });
}

class ShareTranscript {
  final List<ShareEntry> entries;

  const ShareTranscript({required this.entries});
}
