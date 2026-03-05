part of 'app.dart';

enum _EntryKind {
  user,
  assistant,
  toolCall,
  toolCallRef,
  toolResult,
  error,
  system,
  subagent,
  subagentGroup,
  bash
}

class _ConversationEntry {
  final _EntryKind kind;
  final String text;
  final Map<String, dynamic>? args;
  final String? expandedText;
  final _SubagentGroup? group;

  _ConversationEntry._(this.kind, this.text,
      {this.args, this.expandedText, this.group});

  // todo: this is old dart style, use modern syntax or codegen this type of boilerplate
  factory _ConversationEntry.user(String text, {String? expandedText}) =>
      _ConversationEntry._(_EntryKind.user, text, expandedText: expandedText);

  factory _ConversationEntry.assistant(String text) =>
      _ConversationEntry._(_EntryKind.assistant, text);

  factory _ConversationEntry.toolCall(
    String name,
    Map<String, dynamic> args,
  ) =>
      _ConversationEntry._(_EntryKind.toolCall, name, args: args);

  factory _ConversationEntry.toolCallRef(String callId) =>
      _ConversationEntry._(_EntryKind.toolCallRef, callId);

  factory _ConversationEntry.toolResult(String content) =>
      _ConversationEntry._(_EntryKind.toolResult, content);

  factory _ConversationEntry.error(String message) =>
      _ConversationEntry._(_EntryKind.error, message);

  factory _ConversationEntry.subagentGroup(_SubagentGroup group) =>
      _ConversationEntry._(_EntryKind.subagentGroup, '', group: group);

  factory _ConversationEntry.system(String text) =>
      _ConversationEntry._(_EntryKind.system, text);

  factory _ConversationEntry.bash(String command, String output) =>
      _ConversationEntry._(_EntryKind.bash, output, expandedText: command);
}

class _SubagentEntry {
  final String display;
  final String? rawContent;

  _SubagentEntry(this.display, {this.rawContent});

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

class _SubagentGroup {
  final String task;
  final int? index;
  final int? total;
  final List<_SubagentEntry> entries = [];
  bool expanded = false;
  bool done = false;
  String? _currentTool;

  _SubagentGroup({required this.task, this.index, this.total});

  String get summary {
    final prefix = index != null ? '[${index! + 1}/$total]' : '';
    final taskPreview = task.length > 80 ? '${task.substring(0, 80)}…' : task;
    if (done) {
      return '↳ $prefix $taskPreview (${entries.length} steps, done ✓)';
    }
    final activity =
        _currentTool != null ? '${entries.length} steps, $_currentTool…' : '';
    return '↳ $prefix $taskPreview ($activity)';
  }
}

enum _ToolPhase { preparing, awaitingApproval, running, done, denied, error }

class _ToolCallUiState {
  final String id;
  final String name;
  Map<String, dynamic>? args;
  _ToolPhase phase;
  _ToolCallUiState(
      {required this.id,
      required this.name,
      this.phase = _ToolPhase.preparing});

  ToolCallRenderState toRenderState() => ToolCallRenderState(
        name: name,
        args: args,
        phase: switch (phase) {
          _ToolPhase.preparing => ToolCallPhase.preparing,
          _ToolPhase.awaitingApproval => ToolCallPhase.awaitingApproval,
          _ToolPhase.running => ToolCallPhase.running,
          _ToolPhase.done => ToolCallPhase.done,
          _ToolPhase.denied => ToolCallPhase.denied,
          _ToolPhase.error => ToolCallPhase.error,
        },
      );
}

class _TitleTarget {
  final LlmProvider provider;
  final String model;

  const _TitleTarget({
    required this.provider,
    required this.model,
  });
}
