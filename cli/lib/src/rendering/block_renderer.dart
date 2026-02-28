import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/rendering/markdown_renderer.dart';

/// The lifecycle phase of a tool call, used to drive the status suffix
/// displayed next to the tool name in the terminal (e.g. "running…", "denied").
enum ToolCallPhase { preparing, awaitingApproval, running, done, denied, error }

/// Snapshot of a tool call's display state, passed to [BlockRenderer.renderToolCallRef].
///
/// Keeps rendering concerns separate from the agent event model — the renderer
/// never needs to know about [AgentEvent] directly.
class ToolCallRenderState {
  final String name;
  final Map<String, dynamic>? args;
  final ToolCallPhase phase;
  ToolCallRenderState({required this.name, this.args, required this.phase});
}

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
    const header = ' \x1b[1m\x1b[34m❯ You\x1b[0m';
    final body = ansiWrap(text, _inner - 2);
    final indented = body.split('\n').map((l) => '   $l').join('\n');
    return '$header\n$indented';
  }

  /// Render an assistant message block.
  String renderAssistant(String text) {
    const header = ' \x1b[1m\x1b[33m◆ Glue\x1b[0m';
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

  /// Renders a tool call header with a phase-dependent status suffix.
  ///
  /// The [ToolCallRenderState.phase] determines what appears after the tool
  /// name — for example `(preparing…)`, `(running…)`, or nothing at all
  /// when the phase is [ToolCallPhase.done].
  ///
  /// When [state] is null (e.g. the call ID wasn't found), renders a
  /// placeholder `"Tool: ???"` so the UI never breaks.
  String renderToolCallRef(ToolCallRenderState? state) {
    if (state == null) {
      return ' \x1b[1m\x1b[33m▶ Tool: ???\x1b[0m';
    }
    final suffix = switch (state.phase) {
      ToolCallPhase.preparing =>
        ' \x1b[90m(preparing…)\x1b[0m',
      ToolCallPhase.awaitingApproval =>
        ' \x1b[33m(awaiting approval)\x1b[0m',
      ToolCallPhase.running =>
        ' \x1b[36m(running…)\x1b[0m',
      ToolCallPhase.done => '',
      ToolCallPhase.denied =>
        ' \x1b[31m(denied)\x1b[0m',
      ToolCallPhase.error =>
        ' \x1b[31m(error)\x1b[0m',
    };
    final header = ' \x1b[1m\x1b[33m▶ Tool: ${state.name}\x1b[0m$suffix';
    if (state.args == null || state.args!.isEmpty) return header;
    final argsStr = state.args!.entries
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
    const header = ' \x1b[1m\x1b[31m✗ Error\x1b[0m';
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
