import 'dart:convert';

import 'package:glue/src/share/share_models.dart';
import 'package:markdown/markdown.dart' as md;

String shareToolDisplayName(ShareEntry entry) => entry.toolName ?? entry.text;

String shareOutlineLabel(ShareEntryKind kind) => switch (kind) {
      ShareEntryKind.user => 'You',
      ShareEntryKind.assistant => 'Glue',
      ShareEntryKind.toolCall => 'Tool call',
      ShareEntryKind.toolResult => 'Tool result',
      ShareEntryKind.subagentGroup => 'Subagent',
      ShareEntryKind.subagentMessage => 'Subagent message',
    };

String prettyShareJson(Map<String, dynamic> value) =>
    const JsonEncoder.withIndent('  ').convert(value);

String escapeShareHtml(String value) =>
    const HtmlEscape(HtmlEscapeMode.element).convert(value);

String renderAssistantMarkdownHtml(String value) =>
    md.markdownToHtml(escapeShareHtml(value));
