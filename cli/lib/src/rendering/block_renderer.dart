import 'ansi_utils.dart';
import 'markdown_renderer.dart';

/// Renders conversation blocks as styled terminal text.
///
/// A 1-character margin is reserved on each side so output never
/// renders flush against the terminal edges.
class BlockRenderer {
  /// Total terminal width.
  final int width;

  /// Usable content width (excluding 1-char left + right margin).
  int get _inner => (width - 2).clamp(1, width);

  /// Matches grep-style output: file:line:content
  static final _grepLinePattern = RegExp(r'^(\S+?):(\d+):');

  BlockRenderer(this.width);

  /// Wrap a file path in an OSC 8 file:// hyperlink.
  String _linkPath(String path) {
    final uri = 'file://$path';
    return osc8Link(uri, path);
  }

  /// Render a user message block.
  String renderUser(String text) {
    final header = ' \x1b[1m\x1b[34m❯ You\x1b[0m';
    final body =
        wrapIndented(text, _inner, firstPrefix: '   ', nextPrefix: '   ');
    return '$header\n$body';
  }

  /// Render an assistant message block.
  String renderAssistant(String text) {
    final header = ' \x1b[1m\x1b[33m◆ Glue\x1b[0m';
    final md = MarkdownRenderer(_inner - 2);
    final body = md.render(text);
    final indented = body.split('\n').map((l) => '   $l').join('\n');
    return '$header\n$indented';
  }

  /// Render a tool call block.
  String renderToolCall(String name, Map<String, dynamic>? args) {
    final header = ' \x1b[1m\x1b[33m▶ Tool: $name\x1b[0m';
    if (args == null || args.isEmpty) return header;
    final argsStr = args.entries.map((e) {
      final val = '${e.value}';
      final display = ansiTruncate(val, _inner - 6);
      if (e.key == 'path') {
        return '${e.key}: ${_linkPath(display)}';
      }
      return '${e.key}: $display';
    }).join(', ');
    return '$header\n    \x1b[90m$argsStr\x1b[0m';
  }

  /// Render a tool result block.
  String renderToolResult(String content, {bool success = true}) {
    final icon = success ? '✓' : '✗';
    final color = success ? '\x1b[32m' : '\x1b[31m';
    final header = ' \x1b[1m$color$icon Tool result\x1b[0m';
    final truncated = _truncateLines(content, 20, _inner - 2);
    final lines = truncated.split('\n');
    final linked = lines.map((l) {
      final m = _grepLinePattern.firstMatch(l);
      if (m != null) {
        final path = m.group(1)!;
        final rest = l.substring(m.start + path.length);
        return '${_linkPath(path)}$rest';
      }
      return l;
    });
    final indented =
        linked.map((l) => '    \x1b[90m$l\x1b[0m').join('\n');
    return '$header\n$indented';
  }

  /// Render an error block.
  String renderError(String message) {
    final header = ' \x1b[1m\x1b[31m✗ Error\x1b[0m';
    final body = wrapIndented(message, _inner,
        firstPrefix: '    \x1b[31m', nextPrefix: '    \x1b[31m');
    // Close color on each line
    final colored = body.split('\n').map((l) => '$l\x1b[0m').join('\n');
    return '$header\n$colored';
  }

  /// Render a subagent activity entry (indented + dimmed to show hierarchy).
  String renderSubagent(String text) {
    final lines = text.split('\n');
    return lines.map((l) => '      \x1b[2m\x1b[36m$l\x1b[0m').join('\n');
  }

  /// Render a system message block.
  String renderSystem(String text) {
    return ' \x1b[90m$text\x1b[0m';
  }

  String renderBash(String command, String output, {int maxLines = 50}) {
    final boxWidth = _inner;
    final contentWidth = boxWidth - 4;

    final legend = ' $command ';
    final topFill = boxWidth - 2 - legend.length;
    final topBar = topFill > 0 ? '─' * topFill : '';
    final top =
        ' \x1b[90m┌─\x1b[0m\x1b[1m$legend\x1b[0m\x1b[90m$topBar┐\x1b[0m';

    final bottom = ' \x1b[90m└${'─' * (boxWidth - 2)}┘\x1b[0m';

    final lines = output.isEmpty ? <String>[] : output.split('\n');
    final truncated = lines.length > maxLines;
    final visible = truncated ? lines.sublist(lines.length - maxLines) : lines;

    final contentLines = <String>[];
    if (truncated) {
      final notice = '… (${lines.length - maxLines} lines above)';
      final noticeDisplay = visibleLength(notice) > contentWidth
          ? ansiTruncate(notice, contentWidth)
          : notice;
      contentLines.add(
        ' \x1b[90m│ $noticeDisplay${_bashPad(notice, contentWidth)} │\x1b[0m',
      );
    }
    for (final line in visible) {
      final stripped = stripAnsi(line);
      final display = visibleLength(stripped) > contentWidth
          ? ansiTruncate(stripped, contentWidth)
          : stripped;
      contentLines.add(
        ' \x1b[90m│\x1b[0m $display${_bashPad(display, contentWidth)} \x1b[90m│\x1b[0m',
      );
    }

    if (contentLines.isEmpty) {
      contentLines.add(
        ' \x1b[90m│\x1b[0m${' ' * (boxWidth - 2)}\x1b[90m│\x1b[0m',
      );
    }

    return [top, ...contentLines, bottom].join('\n');
  }

  String _bashPad(String text, int width) {
    final vis = visibleLength(text);
    final pad = width - vis;
    return pad > 0 ? ' ' * pad : '';
  }

  String _truncateLines(String s, int maxLines, int maxWidth) {
    final lines = s.split('\n');
    final capped = lines.length > maxLines
        ? [
            ...lines.take(maxLines),
            '  … (${lines.length - maxLines} more lines)',
          ]
        : lines;
    return capped
        .map((l) => visibleLength(l) > maxWidth ? ansiTruncate(l, maxWidth) : l)
        .join('\n');
  }
}
