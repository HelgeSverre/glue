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

  BlockRenderer(this.width);

  /// Render a user message block.
  String renderUser(String text) {
    final header = ' \x1b[1m\x1b[34m❯ You\x1b[0m';
    final body = ansiWrap(text, _inner - 2);
    final indented = body.split('\n').map((l) => '   $l').join('\n');
    return '$header\n$indented';
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
    final argsStr = args.entries
        .map((e) => '${e.key}: ${ansiTruncate('${e.value}', _inner - 6)}')
        .join(', ');
    return '$header\n    \x1b[90m$argsStr\x1b[0m';
  }

  /// Render a tool result block.
  String renderToolResult(String content, {bool success = true}) {
    final icon = success ? '✓' : '✗';
    final color = success ? '\x1b[32m' : '\x1b[31m';
    final header = ' \x1b[1m$color$icon Tool result\x1b[0m';
    final truncated = _truncateLines(content, 20, _inner - 2);
    final indented =
        truncated.split('\n').map((l) => '    \x1b[90m$l\x1b[0m').join('\n');
    return '$header\n$indented';
  }

  /// Render an error block.
  String renderError(String message) {
    final header = ' \x1b[1m\x1b[31m✗ Error\x1b[0m';
    final body = ansiWrap(message, _inner - 2);
    final indented =
        body.split('\n').map((l) => '    \x1b[31m$l\x1b[0m').join('\n');
    return '$header\n$indented';
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
