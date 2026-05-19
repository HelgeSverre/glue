import 'dart:convert';

import 'package:glue_core/glue_core.dart';

/// Kinds of entries that can appear in the rendered conversation transcript.
enum EntryKind {
  user,
  assistant,
  thinking,
  toolCall,
  toolCallRef,
  toolResult,
  error,
  system,
  subagent,
  subagentGroup,
  bash,
}

/// A single entry in the rendered conversation transcript.
///
/// Distinct from `Message` (the LLM-facing wire-shape): a `ConversationEntry`
/// is what the user sees on screen, including system messages, expanded
/// tool-call references, and subagent group folds.
class ConversationEntry {
  final EntryKind kind;
  final String text;
  final Map<String, dynamic>? args;
  final String? expandedText;
  final SubagentGroup? group;

  /// Stable identifier assigned at construction. Used by transcript
  /// selection to anchor positions to a logical block rather than a
  /// transient rendered-line index — line indices shift whenever the
  /// pipeline rebuilds, but a block's identity (and the offset into its
  /// plain text) stays stable across streams and re-renders.
  final String id;

  ConversationEntry._(
    this.kind,
    this.text, {
    this.args,
    this.expandedText,
    this.group,
  }) : id = 'e${_nextId++}';

  static int _nextId = 0;

  factory ConversationEntry.user(String text, {String? expandedText}) =>
      ConversationEntry._(EntryKind.user, text, expandedText: expandedText);

  factory ConversationEntry.assistant(String text) =>
      ConversationEntry._(EntryKind.assistant, text);

  factory ConversationEntry.thinking(String text) =>
      ConversationEntry._(EntryKind.thinking, text);

  factory ConversationEntry.toolCall(
    String name,
    Map<String, dynamic> args,
  ) =>
      ConversationEntry._(EntryKind.toolCall, name, args: args);

  factory ConversationEntry.toolCallRef(ToolCallId callId) =>
      ConversationEntry._(EntryKind.toolCallRef, callId.value);

  factory ConversationEntry.toolResult(String content) =>
      ConversationEntry._(EntryKind.toolResult, content);

  factory ConversationEntry.error(String message) =>
      ConversationEntry._(EntryKind.error, message);

  factory ConversationEntry.subagentGroup(SubagentGroup group) =>
      ConversationEntry._(EntryKind.subagentGroup, '', group: group);

  factory ConversationEntry.system(String text) =>
      ConversationEntry._(EntryKind.system, text);

  factory ConversationEntry.bash(String command, String output) =>
      ConversationEntry._(EntryKind.bash, output, expandedText: command);
}

/// One step inside a subagent group fold (tool call, partial output, etc.).
class SubagentEntry {
  final String display;
  final String? rawContent;

  SubagentEntry(this.display, {this.rawContent});

  String render({required bool expanded}) {
    if (!expanded || rawContent == null) return display;
    final pretty = _tryPrettyJson(rawContent!);
    if (pretty == null) return display;
    final indented = pretty.split('\n').map((l) => '          $l').join('\n');
    return '$display\n$indented';
  }

  static String? _tryPrettyJson(String text) {
    try {
      final parsed = jsonDecode(text);
      if (parsed is Map || parsed is List) {
        return const JsonEncoder.withIndent('  ').convert(parsed);
      }
    } on FormatException {
      // Not JSON.
    }
    return null;
  }
}

/// Foldable group of subagent activity rendered as a single transcript entry.
class SubagentGroup {
  final String task;
  final int? index;
  final int? total;
  final List<SubagentEntry> entries = [];
  bool expanded = false;
  bool done = false;
  String? currentTool;

  SubagentGroup({required this.task, this.index, this.total});

  String get summary {
    final prefix = index != null ? '[${index! + 1}/$total]' : '';
    final taskPreview = task.length > 80 ? '${task.substring(0, 80)}…' : task;
    if (done) {
      return '↳ $prefix $taskPreview (${entries.length} steps, done ✓)';
    }
    final activity =
        currentTool != null ? '${entries.length} steps, $currentTool…' : '';
    return '↳ $prefix $taskPreview ($activity)';
  }
}
