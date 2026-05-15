import 'package:glue_harness/glue_harness.dart';

import 'package:glue/src/conversation/entry.dart';

/// Read/write surface over the on-screen conversation transcript.
///
/// App owns the underlying storage (`_blocks` list, `_streamingText`,
/// `_streamingThinking`, the terminal). The view holds references and
/// callbacks so commands and other consumers can interact with the transcript
/// without reaching into App.
class ConversationView {
  ConversationView({
    required List<ConversationEntry> blocks,
    required Map<String, SubagentGroup> subagentGroups,
    required String Function() streamingTextGetter,
    required void Function() render,
    required void Function() resetStreamingText,
    required void Function() clearScreen,
    required void Function() resetScrollOffset,
    required void Function() clearToolUi,
    required void Function() clearSubagentGroups,
  })  : _blocks = blocks,
        _subagentGroups = subagentGroups,
        _streamingTextGetter = streamingTextGetter,
        _render = render,
        _resetStreamingText = resetStreamingText,
        _clearScreen = clearScreen,
        _resetScrollOffset = resetScrollOffset,
        _clearToolUi = clearToolUi,
        _clearSubagentGroups = clearSubagentGroups;

  final List<ConversationEntry> _blocks;
  final Map<String, SubagentGroup> _subagentGroups;
  final String Function() _streamingTextGetter;
  final void Function() _render;
  final void Function() _resetStreamingText;
  final void Function() _clearScreen;
  final void Function() _resetScrollOffset;
  final void Function() _clearToolUi;
  final void Function() _clearSubagentGroups;

  /// Read-only iterable of currently rendered transcript entries.
  Iterable<ConversationEntry> get entries => List.unmodifiable(_blocks);

  /// In-flight streaming assistant text (empty when no stream is active).
  String get streamingText => _streamingTextGetter();

  /// Returns the most recent assistant text the user can see, including the
  /// in-flight streaming response if any. Returns null if no assistant
  /// content has appeared yet.
  String? lastAssistantText({bool includeStreaming = true}) {
    if (includeStreaming) {
      final partial = _streamingTextGetter();
      if (partial.isNotEmpty) return partial;
    }
    for (var i = _blocks.length - 1; i >= 0; i--) {
      final entry = _blocks[i];
      if (entry.kind == EntryKind.assistant && entry.text.isNotEmpty) {
        return entry.text;
      }
    }
    return null;
  }

  /// Adds a system message and re-renders.
  void notify(String message) {
    _blocks.add(ConversationEntry.system(message));
    _render();
  }

  /// Trigger a re-render without mutating the transcript. Used by panels
  /// that want to refresh their display while polling external state
  /// (e.g., the `/provider add` device-code flow's countdown).
  void render() => _render();

  /// Append an entry to the rendered transcript and re-render. Used when a
  /// command needs to inject something other than a system message
  /// (e.g., tool calls / tool results from skill activation).
  void addEntry(ConversationEntry entry) {
    _blocks.add(entry);
    _render();
  }

  /// Clears the transcript: blocks, in-flight streaming text, screen state.
  /// Used by `/clear`.
  void clear() {
    _blocks.clear();
    _resetStreamingText();
    _resetScrollOffset();
    _clearScreen();
    _render();
  }

  /// Reset all transcript-shape state in preparation for a session replay
  /// (resume or fork). Unlike [clear], this does *not* touch the terminal
  /// screen — the caller will repaint via [appendReplayEntries] and other
  /// notifications. No render is issued.
  void resetForReplay() {
    _blocks.clear();
    _resetStreamingText();
    _resetScrollOffset();
    _clearToolUi();
    _clearSubagentGroups();
  }

  /// Materialise a session's replay log into the rendered transcript.
  /// Reconstructs subagent groups on the fly: spawn opens a group keyed by
  /// `subagent_id`; subsequent events append to that group; completion just
  /// marks it done. Activity without a matching open group is skipped to
  /// avoid silent shape drift.
  void appendReplayEntries(List<SessionReplayEntry> entries) {
    final openGroups = <String, SubagentGroup>{};

    for (final entry in entries) {
      switch (entry.kind) {
        case SessionReplayKind.user:
          _blocks.add(ConversationEntry.user(entry.text));
        case SessionReplayKind.assistant:
          _blocks.add(ConversationEntry.assistant(entry.text));
        case SessionReplayKind.toolCall:
          _blocks.add(ConversationEntry.toolCall(
            entry.toolName ?? entry.text,
            entry.toolArguments ?? const <String, dynamic>{},
          ));
        case SessionReplayKind.toolResult:
          _blocks.add(ConversationEntry.toolResult(entry.text));

        case SessionReplayKind.subagentSpawned:
          final id = entry.subagentId!;
          final group = SubagentGroup(
            task: entry.text,
            index: entry.subagentIndex,
            total: entry.subagentTotal,
          );
          openGroups[id] = group;
          _subagentGroups['${entry.text}:${entry.subagentIndex ?? 0}'] = group;
          _blocks.add(ConversationEntry.subagentGroup(group));

        case SessionReplayKind.subagentEvent:
          final id = entry.subagentId;
          final group = id == null ? null : openGroups[id];
          if (group == null) continue;
          final inner = entry.subagentInner;
          if (inner == null) continue;
          final prefix = group.index != null
              ? '↳ [${group.index! + 1}/${group.total}]'
              : '↳';
          switch (inner.kind) {
            case SessionReplayKind.toolCall:
              final argsPreview =
                  (inner.toolArguments ?? const <String, dynamic>{})
                      .entries
                      .take(2)
                      .map((e) => '${e.key}: ${e.value}')
                      .join(', ');
              group.entries.add(SubagentEntry(
                '$prefix ▶ ${inner.toolName ?? inner.text}  $argsPreview',
              ));
            case SessionReplayKind.toolResult:
              final display = inner.text.length > 80
                  ? '${inner.text.substring(0, 80)}…'
                  : inner.text;
              group.entries.add(SubagentEntry(
                '$prefix ✓ ${display.replaceAll('\n', ' ')}',
                rawContent: inner.text.length > 80 ? inner.text : null,
              ));
            default:
              final display = inner.text.length > 80
                  ? '${inner.text.substring(0, 80)}…'
                  : inner.text;
              group.entries.add(SubagentEntry(
                '$prefix · ${display.replaceAll('\n', ' ')}',
              ));
          }

        case SessionReplayKind.subagentCompleted:
          final id = entry.subagentId;
          final group = id == null ? null : openGroups.remove(id);
          if (group == null) continue;
          group.done = true;
          if (entry.subagentError != null) {
            final prefix = group.index != null
                ? '↳ [${group.index! + 1}/${group.total}]'
                : '↳';
            group.entries
                .add(SubagentEntry('$prefix ✗ Error: ${entry.subagentError}'));
          }
      }
    }

    _render();
  }
}
