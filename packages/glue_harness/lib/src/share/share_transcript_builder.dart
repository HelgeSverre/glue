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
  /// Open groups are tracked in a [Map] keyed by `subagent_id` (not a stack)
  /// so parallel siblings render as siblings, every event is routed to the
  /// matching group, and completions in any order pop the right group.
  ///
  /// Subagent events that arrive without a matching open group (rare —
  /// truncated or malformed sessions) are skipped rather than promoted to
  /// the top level, so the transcript shape never silently inflates.
  ShareTranscript build(List<Map<String, dynamic>> events) {
    final entries = <ShareEntry>[];
    var nextIndex = 1;

    // Open groups keyed by subagent_id. The default Dart `Map` literal is
    // a `LinkedHashMap`, so reverse-order iteration gives "most recently
    // opened first" — used to find a parent group when the spawn event has
    // no `parent_subagent_id` (legacy sessions).
    final openGroups = <String, _OpenGroup>{};

    _OpenGroup? resolveParent(NormalizedSessionEvent event) {
      final explicitParent = event.parentSubagentId;
      if (explicitParent != null && explicitParent.isNotEmpty) {
        final match = openGroups[explicitParent];
        if (match != null) return match;
      }
      // Fallback: pick the most recently opened group whose depth is one
      // shallower than this spawn. Works for legacy `.jsonl` files that
      // predate `parent_subagent_id`.
      final spawnDepth = event.subagentDepth;
      if (spawnDepth != null && spawnDepth > 0) {
        for (final group in openGroups.values.toList().reversed) {
          if (group.depth == spawnDepth - 1) return group;
        }
      }
      return null;
    }

    for (final event in normalizeSessionEvents(events)) {
      switch (event.kind) {
        case NormalizedSessionEventKind.user:
        case NormalizedSessionEventKind.assistant:
        case NormalizedSessionEventKind.toolCall:
        case NormalizedSessionEventKind.toolResult:
          // Top-level events are always appended at the transcript root.
          // Subagents emit their activity via `subagent_event`, so reaching
          // this branch means the event came from the parent agent — even
          // while subagents are mid-flight.
          entries.add(ShareEntry(
            index: nextIndex++,
            kind: switch (event.kind) {
              NormalizedSessionEventKind.user => ShareEntryKind.user,
              NormalizedSessionEventKind.assistant => ShareEntryKind.assistant,
              NormalizedSessionEventKind.toolCall => ShareEntryKind.toolCall,
              NormalizedSessionEventKind.toolResult =>
                ShareEntryKind.toolResult,
              _ => ShareEntryKind.assistant,
            },
            text: event.visibleText,
            toolName: event.toolName,
            toolArguments: event.kind == NormalizedSessionEventKind.toolCall
                ? (event.toolArguments ?? const <String, dynamic>{})
                : null,
            nestingLevel: 0,
          ));
        case NormalizedSessionEventKind.subagentSpawned:
          final parent = resolveParent(event);
          final children = <ShareEntry>[];
          final nestingLevel = parent == null ? 0 : parent.nestingLevel + 1;
          final group = ShareEntry(
            index: nextIndex++,
            kind: ShareEntryKind.subagentGroup,
            text: event.text,
            subagentId: event.subagentId,
            nestingLevel: nestingLevel,
            children: children,
          );
          if (parent == null) {
            entries.add(group);
          } else {
            parent.children.add(group);
          }
          openGroups[event.subagentId!] = _OpenGroup(
            subagentId: event.subagentId!,
            children: children,
            nestingLevel: nestingLevel,
            depth: event.subagentDepth ?? 0,
          );
        case NormalizedSessionEventKind.subagentEvent:
          final group = openGroups[event.subagentId];
          if (group == null) {
            // Forwarded event without a matching open group — skip safely.
            continue;
          }
          final inner = event.subagentInner!;
          final childKind = switch (inner.kind) {
            NormalizedSessionEventKind.toolCall => ShareEntryKind.toolCall,
            NormalizedSessionEventKind.toolResult => ShareEntryKind.toolResult,
            _ => ShareEntryKind.subagentMessage,
          };
          group.children.add(ShareEntry(
            index: nextIndex++,
            kind: childKind,
            text: inner.visibleText,
            toolName: inner.toolName,
            toolArguments: inner.toolArguments,
            subagentId: event.subagentId,
            nestingLevel: group.nestingLevel + 1,
          ));
        case NormalizedSessionEventKind.subagentCompleted:
          openGroups.remove(event.subagentId);
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
  final int depth;

  _OpenGroup({
    required this.subagentId,
    required this.children,
    required this.nestingLevel,
    required this.depth,
  });
}
