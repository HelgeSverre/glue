import 'ansi_utils.dart';
import 'markdown_renderer.dart';
import '../terminal/styled.dart';

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
    final header = ' ${'❯ You'.styled.bold.blue}';
    final body =
        wrapIndented(text, _inner, firstPrefix: '   ', nextPrefix: '   ');
    return '$header\n$body';
  }

  /// Render an assistant message block.
  String renderAssistant(String text) {
    final header = ' ${'◆ Glue'.styled.bold.yellow}';
    final md = MarkdownRenderer(_inner - 2);
    final body = md.render(text);
    final indented = body.split('\n').map((l) => '   $l').join('\n');
    return '$header\n$indented';
  }

  /// Render a tool call block.
  String renderToolCall(String name, Map<String, dynamic>? args) {
    final header = ' ${'▶ Tool: $name'.styled.bold.yellow}';
    if (args == null || args.isEmpty) return header;
    final argsStr = args.entries
        .map((e) => '${e.key}: ${ansiTruncate('${e.value}', _inner - 6)}')
        .join(', ');
    return '$header\n    ${argsStr.styled.gray}';
  }

  /// Render a tool result block.
  String renderToolResult(String content, {bool success = true}) {
    final icon = success ? '✓' : '✗';
    final headerText = '$icon Tool result';
    final header =
        ' ${success ? headerText.styled.bold.green : headerText.styled.bold.red}';
    final truncated = _truncateLines(content, 20, _inner - 2);
    final indented =
        truncated.split('\n').map((l) => '    ${l.styled.gray}').join('\n');
    return '$header\n$indented';
  }

  /// Render an error block.
  String renderError(String message) {
    final header = ' ${'✗ Error'.styled.bold.red}';
    final body = wrapIndented(message, _inner,
        firstPrefix: '    ', nextPrefix: '    ');
    // Apply red styling to each line
    final colored = body.split('\n').map((l) => l.styled.red.toString()).join('\n');
    return '$header\n$colored';
  }

  /// Render a subagent activity entry (indented + dimmed to show hierarchy).
  String renderSubagent(String text) {
    final lines = text.split('\n');
    return lines.map((l) => '      ${l.styled.dim.cyan}').join('\n');
  }

  /// Render a system message block.
  String renderSystem(String text) {
    return ' ${text.styled.gray}';
  }

  String renderBash(String command, String output, {int maxLines = 50}) {
    final boxWidth = _inner;
    final contentWidth = boxWidth - 4;

    final legend = ' $command ';
    final topFill = boxWidth - 2 - legend.length;
    final topBar = topFill > 0 ? '─' * topFill : '';
    final top =
        ' ${'┌─'.styled.gray}${legend.styled.bold}${'$topBar┐'.styled.gray}';

    final bottom = ' ${'└${'─' * (boxWidth - 2)}┘'.styled.gray}';

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
        ' ${'│ $noticeDisplay${_bashPad(notice, contentWidth)} │'.styled.gray}',
      );
    }
    for (final line in visible) {
      final stripped = stripAnsi(line);
      final display = visibleLength(stripped) > contentWidth
          ? ansiTruncate(stripped, contentWidth)
          : stripped;
      contentLines.add(
        ' ${'│'.styled.gray} $display${_bashPad(display, contentWidth)} ${'│'.styled.gray}',
      );
    }

    if (contentLines.isEmpty) {
      contentLines.add(
        ' ${'│'.styled.gray}${' ' * (boxWidth - 2)}${'│'.styled.gray}',
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
