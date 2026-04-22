import 'package:glue/src/share/share_models.dart';
import 'package:glue/src/share/renderer/renderer_support.dart';
import 'package:glue/src/storage/session_store.dart';

class ShareMarkdownRenderer {
  String render({
    required SessionMeta meta,
    required ShareTranscript transcript,
    required DateTime exportedAt,
  }) {
    final out = StringBuffer()
      ..writeln('# Glue Session')
      ..writeln()
      ..writeln('> **Session ID:** `${meta.id}`');

    if ((meta.title ?? '').trim().isNotEmpty) {
      out.writeln('> **Title:** ${meta.title}');
    }

    out
      ..writeln('> **Model:** `${meta.modelRef}`')
      ..writeln('> **Started:** ${meta.startTime.toUtc().toIso8601String()}')
      ..writeln('> **Exported:** ${exportedAt.toUtc().toIso8601String()}')
      ..writeln('> **Directory:** `${meta.cwd}`')
      ..writeln();

    for (final entry in transcript.entries) {
      _writeEntry(out, entry);
    }

    return '${out.toString().trimRight()}\n';
  }

  void _writeEntry(StringBuffer out, ShareEntry entry) {
    out
      ..writeln('---')
      ..writeln()
      ..writeln('<a id="entry-${entry.index}"></a>');

    switch (entry.kind) {
      case ShareEntryKind.user:
        out
          ..writeln('## User')
          ..writeln()
          ..writeln(entry.text)
          ..writeln();
      case ShareEntryKind.assistant:
        out
          ..writeln('## Glue')
          ..writeln()
          ..writeln(entry.text)
          ..writeln();
      case ShareEntryKind.toolCall:
        out
          ..writeln('## Tool: ${shareToolDisplayName(entry)}')
          ..writeln()
          ..writeln('### Arguments')
          ..writeln()
          ..writeln('```json')
          ..writeln(
              prettyShareJson(entry.toolArguments ?? const <String, dynamic>{}))
          ..writeln('```')
          ..writeln();
      case ShareEntryKind.toolResult:
        out
          ..writeln('## Tool result')
          ..writeln()
          ..writeln('```text')
          ..writeln(entry.text)
          ..writeln('```')
          ..writeln();
      case ShareEntryKind.subagentGroup:
        out
          ..writeln('## Subagent: ${entry.text}')
          ..writeln();
        for (final child in entry.children) {
          _writeNested(out, child, depth: 1);
        }
        out.writeln();
      case ShareEntryKind.subagentMessage:
        out
          ..writeln('## Subagent')
          ..writeln()
          ..writeln('> ${entry.text}')
          ..writeln();
    }
  }

  void _writeNested(StringBuffer out, ShareEntry entry, {required int depth}) {
    final heading = '#' * (depth + 2);
    switch (entry.kind) {
      case ShareEntryKind.subagentGroup:
        out
          ..writeln('$heading Subagent: ${entry.text}')
          ..writeln();
        for (final child in entry.children) {
          _writeNested(out, child, depth: depth + 1);
        }
      case ShareEntryKind.subagentMessage:
        out
          ..writeln('> ${entry.text}')
          ..writeln();
      case ShareEntryKind.toolCall:
        out
          ..writeln('$heading Tool: ${shareToolDisplayName(entry)}')
          ..writeln()
          ..writeln('```json')
          ..writeln(
              prettyShareJson(entry.toolArguments ?? const <String, dynamic>{}))
          ..writeln('```')
          ..writeln();
      case ShareEntryKind.toolResult:
        out
          ..writeln('$heading Tool result')
          ..writeln()
          ..writeln('```text')
          ..writeln(entry.text)
          ..writeln('```')
          ..writeln();
      case ShareEntryKind.user:
      case ShareEntryKind.assistant:
        out
          ..writeln(entry.text)
          ..writeln();
    }
  }
}
