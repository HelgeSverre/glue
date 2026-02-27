import 'dart:math';

import 'ansi_utils.dart';

/// Renders a subset of Markdown to ANSI-styled terminal text.
///
/// Supported:
/// - Headings: #, ##, ###
/// - Bold: **text**
/// - Italic: *text*
/// - Inline code: `code`
/// - Fenced code blocks: ```lang ... ```
/// - Unordered lists: - item, * item
/// - Ordered lists: 1. item
/// - Blockquotes: > text
/// - Links: [text](url)
/// - Tables: | col | col |
class MarkdownRenderer {
  final int width;

  static final _tableRowPattern = RegExp(r'^\s*\|.*\|\s*$');
  static final _tableSepPattern = RegExp(r'^\s*\|[\s:?\-|]+\|\s*$');

  MarkdownRenderer(this.width);

  /// Render markdown text to ANSI-styled terminal output.
  String render(String markdown) {
    final lines = markdown.split('\n');
    final output = <String>[];
    var inCodeBlock = false;
    String? codeBlockLang;
    final codeLines = <String>[];
    final tableLines = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Fenced code blocks
      if (line.trimLeft().startsWith('```')) {
        if (!inCodeBlock) {
          _flushTable(tableLines, output);
          inCodeBlock = true;
          codeBlockLang = line.trimLeft().substring(3).trim();
          if (codeBlockLang.isEmpty) codeBlockLang = null;
          continue;
        } else {
          output.addAll(_renderCodeBlock(codeLines, codeBlockLang));
          codeLines.clear();
          inCodeBlock = false;
          codeBlockLang = null;
          continue;
        }
      }

      if (inCodeBlock) {
        codeLines.add(line);
        continue;
      }

      // Table detection: collect consecutive pipe-delimited lines
      if (_tableRowPattern.hasMatch(line)) {
        tableLines.add(line);
        continue;
      }

      _flushTable(tableLines, output);

      // Headings
      if (line.startsWith('### ')) {
        output.add('\x1b[1m\x1b[33m${line.substring(4)}\x1b[0m');
        continue;
      }
      if (line.startsWith('## ')) {
        output.add('\x1b[1m\x1b[33m${line.substring(3)}\x1b[0m');
        continue;
      }
      if (line.startsWith('# ')) {
        output.add('\x1b[1m\x1b[33m${line.substring(2)}\x1b[0m');
        continue;
      }

      // Blockquote
      if (line.startsWith('> ')) {
        output.add('\x1b[90m│ ${_renderInline(line.substring(2))}\x1b[0m');
        continue;
      }

      // Unordered list
      final ulMatch = RegExp(r'^(\s*)[-*] (.*)').firstMatch(line);
      if (ulMatch != null) {
        final indent = ulMatch.group(1)!;
        final content = _renderInline(ulMatch.group(2)!);
        output.add('$indent• $content');
        continue;
      }

      // Ordered list
      final olMatch = RegExp(r'^(\s*)(\d+)\. (.*)').firstMatch(line);
      if (olMatch != null) {
        final indent = olMatch.group(1)!;
        final num = olMatch.group(2)!;
        final content = _renderInline(olMatch.group(3)!);
        output.add('$indent$num. $content');
        continue;
      }

      // Regular paragraph line
      if (line.isEmpty) {
        output.add('');
      } else {
        output.add(_renderInline(line));
      }
    }

    _flushTable(tableLines, output);

    // Close any unclosed code block
    if (inCodeBlock && codeLines.isNotEmpty) {
      output.addAll(_renderCodeBlock(codeLines, codeBlockLang));
    }

    return output.join('\n');
  }

  /// Render inline markdown: **bold**, *italic*, `code`, [links](url)
  String _renderInline(String text) {
    // Extract inline code spans first to protect their contents from further
    // inline processing (e.g. links/bold inside backticks).
    final segments = <String>[];
    var remaining = text;
    final codeRe = RegExp(r'`(.+?)`');
    while (true) {
      final m = codeRe.firstMatch(remaining);
      if (m == null) break;
      segments.add(_renderInlineSegment(remaining.substring(0, m.start)));
      segments.add('\x1b[33m${m.group(1)}\x1b[39m');
      remaining = remaining.substring(m.end);
    }
    segments.add(_renderInlineSegment(remaining));
    return segments.join();
  }

  String _renderInlineSegment(String text) {
    // Bold: **text**
    text = text.replaceAllMapped(
      RegExp(r'\*\*(.+?)\*\*'),
      (m) => '\x1b[1m${m.group(1)}\x1b[22m',
    );
    // Italic: *text* (but not inside **)
    text = text.replaceAllMapped(
      RegExp(r'(?<!\*)\*([^*]+?)\*(?!\*)'),
      (m) => '\x1b[3m${m.group(1)}\x1b[23m',
    );
    // Links: [text](url)
    text = text.replaceAllMapped(
      RegExp(r'\[(.+?)\]\((.+?)\)'),
      (m) => '${m.group(1)} \x1b[90m(${m.group(2)})\x1b[0m',
    );
    return text;
  }

  /// Render a fenced code block with box-drawing characters.
  List<String> _renderCodeBlock(List<String> lines, String? lang) {
    final codeWidth = (width - 4).clamp(20, width);
    final label = lang != null ? ' $lang ' : '';
    final headerRuleLen = codeWidth - 2 - label.length;
    final headerRule = headerRuleLen > 0 ? '─' * headerRuleLen : '';

    final output = <String>[];
    output.add('\x1b[90m╭─$label$headerRule╮\x1b[0m');
    for (final line in lines) {
      final truncated = visibleLength(line) > codeWidth - 4
          ? ansiTruncate(line, codeWidth - 4)
          : line;
      final pad = (codeWidth - 4) - visibleLength(truncated);
      final padded = pad > 0 ? '$truncated${' ' * pad}' : truncated;
      output.add('\x1b[90m│\x1b[0m \x1b[2m$padded\x1b[22m \x1b[90m│\x1b[0m');
    }
    output.add('\x1b[90m╰${'─' * (codeWidth - 2)}╯\x1b[0m');
    return output;
  }

  // ── Table rendering ───────────────────────────────────────────────────

  void _flushTable(List<String> tableLines, List<String> output) {
    if (tableLines.isEmpty) return;

    // Need at least header + separator + one body row, or header + separator
    final rows = <List<String>>[];
    int? separatorIdx;

    for (var i = 0; i < tableLines.length; i++) {
      if (_tableSepPattern.hasMatch(tableLines[i])) {
        if (separatorIdx == null) {
          separatorIdx = i;
          continue;
        }
      }
      rows.add(_parseTableRow(tableLines[i]));
    }

    tableLines.clear();

    if (rows.isEmpty) return;

    // Normalize column count
    final colCount = rows.map((r) => r.length).reduce(max);
    for (final row in rows) {
      while (row.length < colCount) {
        row.add('');
      }
    }

    // Pre-render all cells so widths reflect actual visible output
    final rendered =
        rows.map((row) => row.map(_renderInline).toList()).toList();

    // Compute column widths from rendered visible text
    final widths = List<int>.filled(colCount, 0);
    for (final row in rendered) {
      for (var c = 0; c < colCount; c++) {
        widths[c] = max(widths[c], visibleLength(row[c]));
      }
    }

    // Clamp total width to available space
    final totalWidth = widths.fold<int>(0, (s, w) => s + w) + colCount * 3 + 1;
    if (totalWidth > width) {
      final excess = totalWidth - width;
      // Shrink widest columns first
      var remaining = excess;
      while (remaining > 0) {
        final maxW = widths.reduce(max);
        if (maxW <= 1) break;
        for (var c = 0; c < colCount && remaining > 0; c++) {
          if (widths[c] == maxW) {
            widths[c]--;
            remaining--;
          }
        }
      }
    }

    // Header row index
    final headerEnd = separatorIdx ?? 1;

    output.add(_tableRule(widths, '┌', '┬', '┐'));

    for (var r = 0; r < rendered.length; r++) {
      final isHeader = r < headerEnd;
      output.add(_tableDataRow(rendered[r], widths, bold: isHeader));
      if (r == headerEnd - 1 && rendered.length > headerEnd) {
        output.add(_tableRule(widths, '├', '┼', '┤'));
      }
    }

    output.add(_tableRule(widths, '└', '┴', '┘'));
  }

  List<String> _parseTableRow(String line) {
    var trimmed = line.trim();
    if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
    if (trimmed.endsWith('|')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed.split('|').map((c) => c.trim()).toList();
  }

  String _tableRule(List<int> widths, String left, String mid, String right) {
    final parts = widths.map((w) => '─' * (w + 2));
    return '\x1b[90m$left${parts.join(mid)}$right\x1b[0m';
  }

  String _tableDataRow(List<String> cells, List<int> widths,
      {bool bold = false}) {
    final parts = <String>[];
    for (var c = 0; c < cells.length; c++) {
      final cell = cells[c];
      final vis = visibleLength(cell);
      final colW = widths[c];
      final display = vis > colW ? ansiTruncate(cell, colW) : cell;
      final pad = colW - (vis > colW ? colW : vis);
      final content =
          bold ? '\x1b[1m$display\x1b[22m${' ' * pad}' : '$display${' ' * pad}';
      parts.add(' $content ');
    }
    return '\x1b[90m│\x1b[0m${parts.join('\x1b[90m│\x1b[0m')}\x1b[90m│\x1b[0m';
  }
}
