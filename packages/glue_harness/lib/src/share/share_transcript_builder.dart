import 'package:glue_harness/src/session/session_event_normalizer.dart';
import 'package:glue_harness/src/share/share_models.dart';

class ShareTranscriptBuilder {
  /// Builds a share transcript from persisted `conversation.jsonl` rows.
  ///
  /// Top-level user/assistant/tool events become flat entries. Subagent
  /// activity is grouped into nested [ShareEntryKind.subagentGroup] entries
  /// keyed by `subagent_id`, with each forwarded inner event rendered as a
  /// child [ShareEntryKind.subagentMessage] / [ShareEntryKind.toolCall] /
  /// [ShareEntryKind.toolResult] under the group.
  ///
  /// Subagent events that arrive without a matching open group (rare —
  /// truncated or malformed sessions) are skipped rather than promoted to
  /// the top level, so the transcript shape never silently inflates.
  ShareTranscript build(List<Map<String, dynamic>> events) {
    final entries = <ShareEntry>[];
    var nextIndex = 1;

    // Stack of open subagent groups. Each frame holds the group's mutable
    // children buffer plus the nesting level for new children.
    final stack = <_OpenGroup>[];

    void appendEntry(ShareEntry entry) {
      if (stack.isEmpty) {
        entries.add(entry);
      } else {
        stack.last.children.add(entry);
      }
    }

    int nestingLevel() => stack.isEmpty ? 0 : stack.last.nestingLevel + 1;

    for (final event in normalizeSessionEvents(events)) {
      switch (event.kind) {
        case NormalizedSessionEventKind.user:
          appendEntry(ShareEntry(
            index: nextIndex++,
            kind: ShareEntryKind.user,
            text: event.visibleText,
            nestingLevel: nestingLevel(),
          ));
        case NormalizedSessionEventKind.assistant:
          appendEntry(ShareEntry(
            index: nextIndex++,
            kind: ShareEntryKind.assistant,
            text: event.visibleText,
            nestingLevel: nestingLevel(),
          ));
        case NormalizedSessionEventKind.toolCall:
          appendEntry(ShareEntry(
            index: nextIndex++,
            kind: ShareEntryKind.toolCall,
            text: event.visibleText,
            toolName: event.toolName,
            toolArguments: event.toolArguments ?? const <String, dynamic>{},
            nestingLevel: nestingLevel(),
          ));
        case NormalizedSessionEventKind.toolResult:
          appendEntry(ShareEntry(
            index: nextIndex++,
            kind: ShareEntryKind.toolResult,
            text: event.visibleText,
            nestingLevel: nestingLevel(),
          ));
        case NormalizedSessionEventKind.subagentSpawned:
          final children = <ShareEntry>[];
          final group = ShareEntry(
            index: nextIndex++,
            kind: ShareEntryKind.subagentGroup,
            text: event.text,
            subagentId: event.subagentId,
            nestingLevel: nestingLevel(),
            children: children,
          );
          appendEntry(group);
          stack.add(_OpenGroup(
            subagentId: event.subagentId!,
            children: children,
            nestingLevel: group.nestingLevel,
          ));
        case NormalizedSessionEventKind.subagentEvent:
          if (stack.isEmpty || stack.last.subagentId != event.subagentId) {
            // Forwarded event without a matching open group — skip safely.
            continue;
          }
          final inner = event.subagentInner!;
          final childKind = switch (inner.kind) {
            NormalizedSessionEventKind.toolCall => ShareEntryKind.toolCall,
            NormalizedSessionEventKind.toolResult => ShareEntryKind.toolResult,
            _ => ShareEntryKind.subagentMessage,
          };
          stack.last.children.add(ShareEntry(
            index: nextIndex++,
            kind: childKind,
            text: inner.visibleText,
            toolName: inner.toolName,
            toolArguments: inner.toolArguments,
            subagentId: event.subagentId,
            nestingLevel: stack.last.nestingLevel + 1,
          ));
        case NormalizedSessionEventKind.subagentCompleted:
          if (stack.isNotEmpty && stack.last.subagentId == event.subagentId) {
            stack.removeLast();
          }
      }
    }

    return ShareTranscript(entries: entries);
  }

  /// Builds a share transcript from already-normalized entries.
  ///
  /// Retained as a fixture seam for tests that want to construct exact
  /// transcript shapes without round-tripping through JSONL.
  ShareTranscript fromEntries(List<ShareEntry> entries) {
    return ShareTranscript(entries: entries);
  }
}

class _OpenGroup {
  final String subagentId;
  final List<ShareEntry> children;
  final int nestingLevel;

  _OpenGroup({
    required this.subagentId,
    required this.children,
    required this.nestingLevel,
  });
}
