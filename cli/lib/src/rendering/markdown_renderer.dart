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
  // ')' is excluded to avoid capturing trailing parens in prose like "(see https://...)".
  // URLs containing literal parens (e.g. Wikipedia links) will be truncated at the
  // first ')'. This is the standard trade-off for bare URL heuristics.
  // The lookbehinds prevent re-matching URLs already inside OSC 8 sequences:
  //   - (?<!\x1b\]8;;) skips URLs in the href position
  //   - (?<!\x07) skips URLs in the display text position
  static final _bareUrlPattern = RegExp(
    r'(?<!\x1b\]8;;)(?<!\x07)https?://[^\s<>\[\])`\x07\x1b' "'" r'"]+',
  );

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

      // Headings — wrap raw text first, then style each line so
      // continuation lines retain bold+yellow.
      if (line.startsWith('### ')) {
        final wrapped = ansiWrap(line.substring(4), width);
        output.addAll(wrapped.split('\n').map(
            (l) => '\x1b[1m\x1b[33m$l\x1b[0m'));
        continue;
      }
      if (line.startsWith('## ')) {
        final wrapped = ansiWrap(line.substring(3), width);
        output.addAll(wrapped.split('\n').map(
            (l) => '\x1b[1m\x1b[33m$l\x1b[0m'));
        continue;
      }
      if (line.startsWith('# ')) {
        final wrapped = ansiWrap(line.substring(2), width);
        output.addAll(wrapped.split('\n').map(
            (l) => '\x1b[1m\x1b[33m$l\x1b[0m'));
        continue;
      }

      // Blockquote
      if (line.startsWith('> ')) {
        final content = _renderInline(line.substring(2));
        final wrapped = wrapIndented(content, width,
            firstPrefix: '\x1b[90m│ \x1b[0m', nextPrefix: '\x1b[90m│ \x1b[0m');
        output.addAll(wrapped.split('\n'));
        continue;
      }

      // Unordered list
      final ulMatch = RegExp(r'^(\s*)[-*] (.*)').firstMatch(line);
      if (ulMatch != null) {
        final indent = ulMatch.group(1)!;
        final content = _renderInline(ulMatch.group(2)!);
        final bullet = '$indent• ';
        final contPad = '$indent  ';
        final wrapped = wrapIndented(content, width,
            firstPrefix: bullet, nextPrefix: contPad);
        output.addAll(wrapped.split('\n'));
        continue;
      }

      // Ordered list
      final olMatch = RegExp(r'^(\s*)(\d+)\. (.*)').firstMatch(line);
      if (olMatch != null) {
        final indent = olMatch.group(1)!;
        final num = olMatch.group(2)!;
        final content = _renderInline(olMatch.group(3)!);
        final prefix = '$indent$num. ';
        final contPad = '$indent${' ' * (num.length + 2)}';
        final wrapped = wrapIndented(content, width,
            firstPrefix: prefix, nextPrefix: contPad);
        output.addAll(wrapped.split('\n'));
        continue;
      }

      // Regular paragraph line
      if (line.isEmpty) {
        output.add('');
      } else {
        output.addAll(ansiWrap(_renderInline(line), width).split('\n'));
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
    // Links: [text](url) → OSC 8 clickable link, underlined
    text = text.replaceAllMapped(
      RegExp(r'\[(.+?)\]\((.+?)\)'),
      (m) => '\x1b[4m${osc8Link(m.group(2)!, m.group(1))}\x1b[24m',
    );
    // Bare URLs: https://... and http://...
    // Runs after markdown links. The lookbehinds prevent re-matching URLs
    // already inside OSC 8 sequences (href position after \x1b]8;; and
    // display text position after \x07).
    text = text.replaceAllMapped(
      _bareUrlPattern,
      (m) {
        var url = m.group(0)!;
        // Strip trailing punctuation that's likely not part of the URL
        var suffix = '';
        while (url.isNotEmpty && '.,;:!?)'.contains(url[url.length - 1])) {
          suffix = url[url.length - 1] + suffix;
          url = url.substring(0, url.length - 1);
        }
        return '${osc8Link(url)}$suffix';
      },
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
