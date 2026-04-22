import 'package:glue/src/session/session_event_normalizer.dart';
import 'package:glue/src/share/share_models.dart';

class ShareTranscriptBuilder {
  /// Builds a share transcript from persisted `conversation.jsonl` rows.
  ///
  /// Only event families currently normalized by [normalizeSessionEvents]
  /// participate here. Richer transcript shapes such as nested subagent
  /// groups stay explicit in [fromEntries] until Glue persists a shareable
  /// subagent schema instead of UI-only updates.
  ShareTranscript build(List<Map<String, dynamic>> events) {
    final entries = <ShareEntry>[];
    var nextIndex = 1;

    for (final event in normalizeSessionEvents(events)) {
      switch (event.kind) {
        case NormalizedSessionEventKind.user:
          entries.add(ShareEntry(
            index: nextIndex++,
            kind: ShareEntryKind.user,
            text: event.visibleText,
          ));
        case NormalizedSessionEventKind.assistant:
          entries.add(ShareEntry(
            index: nextIndex++,
            kind: ShareEntryKind.assistant,
            text: event.visibleText,
          ));
        case NormalizedSessionEventKind.toolCall:
          entries.add(ShareEntry(
            index: nextIndex++,
            kind: ShareEntryKind.toolCall,
            text: event.visibleText,
            toolName: event.toolName,
            toolArguments: event.toolArguments ?? const <String, dynamic>{},
          ));
        case NormalizedSessionEventKind.toolResult:
          entries.add(ShareEntry(
            index: nextIndex++,
            kind: ShareEntryKind.toolResult,
            text: event.visibleText,
          ));
      }
    }

    return ShareTranscript(entries: entries);
  }

  /// Builds a share transcript from already-normalized entries.
  ///
  /// This is the extension seam for richer future transcript sources such as
  /// persisted subagent hierarchies, without teaching raw JSONL parsing about
  /// hypothetical event families before they exist in the session schema.
  ShareTranscript fromEntries(List<ShareEntry> entries) {
    return ShareTranscript(entries: entries);
  }
}
