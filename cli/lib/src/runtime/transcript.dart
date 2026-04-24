import 'dart:convert';

import 'package:glue/src/ui/rendering/block_renderer.dart';

/// Visible category for a single entry in the conversation transcript.
enum EntryKind {
  user,
  assistant,
  toolCall,
  toolCallRef,
  toolResult,
  error,
  system,
  subagent,
  subagentGroup,
  bash,
}

/// One rendered entry in the conversation transcript. The app's block list
/// holds these in the order they should be displayed.
class ConversationEntry {
  final EntryKind kind;
  final String text;
  final Map<String, dynamic>? args;
  final String? expandedText;
  final SubagentGroup? group;

  ConversationEntry._(
    this.kind,
    this.text, {
    this.args,
    this.expandedText,
    this.group,
  });

  factory ConversationEntry.user(String text, {String? expandedText}) =>
      ConversationEntry._(EntryKind.user, text, expandedText: expandedText);

  factory ConversationEntry.assistant(String text) =>
      ConversationEntry._(EntryKind.assistant, text);

  factory ConversationEntry.toolCall(String name, Map<String, dynamic> args) =>
      ConversationEntry._(EntryKind.toolCall, name, args: args);

  factory ConversationEntry.toolCallRef(String callId) =>
      ConversationEntry._(EntryKind.toolCallRef, callId);

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

/// One line of activity inside a subagent run — a single tool call or
/// status update, batched into a [SubagentGroup].
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

/// A batch of subagent activity that collapses into a single transcript line
/// while running and expands on user toggle.
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

/// Lifecycle phase of a rendered tool call. Drives the spinner/status shown
/// alongside the tool name in the transcript.
enum ToolPhase {
  preparing,
  awaitingApproval,
  running,
  done,
  denied,
  cancelled,
  error,
}

/// Mutable per-tool-call UI state, keyed by call id. Updated as the tool moves
/// through [ToolPhase] transitions.
class ToolCallUiState {
  final String id;
  final String name;
  Map<String, dynamic>? args;
  ToolPhase phase;

  ToolCallUiState({
    required this.id,
    required this.name,
    this.phase = ToolPhase.preparing,
  });

  ToolCallRenderState toRenderState() => ToolCallRenderState(
        name: name,
        args: args,
        phase: switch (phase) {
          ToolPhase.preparing => ToolCallPhase.preparing,
          ToolPhase.awaitingApproval => ToolCallPhase.awaitingApproval,
          ToolPhase.running => ToolCallPhase.running,
          ToolPhase.done => ToolCallPhase.done,
          ToolPhase.denied => ToolCallPhase.denied,
          ToolPhase.cancelled => ToolCallPhase.cancelled,
          ToolPhase.error => ToolCallPhase.error,
        },
      );
}

/// The conversation UI state — what the user sees scrolling through the
/// terminal. Owns the block list, per-tool UI state, scroll offset,
/// in-progress streaming buffer, and subagent event grouping.
///
/// Features mutate this through narrow methods (e.g. [postNotice]) or by
/// reaching for the appropriate collection directly. The app keeps exactly
/// one [Transcript]; there is no interface (no second implementation needed,
/// tests construct one directly).
class Transcript {
  /// All rendered blocks, in the order they should be displayed.
  final List<ConversationEntry> blocks = [];

  /// Per-tool-call UI state, keyed by call id.
  final Map<String, ToolCallUiState> toolUi = {};

  /// Subagent groups, keyed by subagent id.
  final Map<String, SubagentGroup> subagentGroups = {};

  /// For each logical output line, the subagent group it belongs to (or null
  /// for top-level lines). Keeps line-level grouping in sync with blocks.
  final List<SubagentGroup?> outputLineGroups = [];

  /// Scroll offset from the bottom of the transcript, in lines.
  int scrollOffset = 0;

  /// In-progress streaming text for the assistant's current response.
  String streamingText = '';

  /// Clear everything (used by `/clear`).
  void clear() {
    blocks.clear();
    toolUi.clear();
    subagentGroups.clear();
    outputLineGroups.clear();
    scrollOffset = 0;
    streamingText = '';
  }

  /// Append a system-visible notice as a new block.
  void postNotice(String text) {
    blocks.add(ConversationEntry.system(text));
  }
}
