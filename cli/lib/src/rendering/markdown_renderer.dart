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
class MarkdownRenderer {
  final int width;

  MarkdownRenderer(this.width);

  /// Render markdown text to ANSI-styled terminal output.
  String render(String markdown) {
    final lines = markdown.split('\n');
    final output = <String>[];
    var inCodeBlock = false;
    String? codeBlockLang;
    final codeLines = <String>[];

    for (final line in lines) {
      // Fenced code blocks
      if (line.trimLeft().startsWith('```')) {
        if (!inCodeBlock) {
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

    // Close any unclosed code block
    if (inCodeBlock && codeLines.isNotEmpty) {
      output.addAll(_renderCodeBlock(codeLines, codeBlockLang));
    }

    return output.join('\n');
  }

  /// Render inline markdown: **bold**, *italic*, `code`, [links](url)
  String _renderInline(String text) {
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
    // Inline code: `code`
    text = text.replaceAllMapped(
      RegExp(r'`(.+?)`'),
      (m) => '\x1b[33m${m.group(1)}\x1b[39m',
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
}
