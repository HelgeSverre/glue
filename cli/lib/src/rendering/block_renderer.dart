import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/rendering/markdown_renderer.dart';
import 'package:glue/src/terminal/styled.dart';

/// The lifecycle phase of a tool call, used to drive the status suffix
/// displayed next to the tool name in the terminal (e.g. "running…", "denied").
///
/// Semantics:
/// - [preparing]: model named the tool; arguments still streaming.
/// - [awaitingApproval]: user decision required before execution.
/// - [running]: Glue is actively executing the tool.
/// - [done]: tool completed successfully.
/// - [denied]: user or policy refused execution before it ran.
/// - [cancelled]: user cancelled while the tool was active (Ctrl+C or
///   `/cancel`). Distinct from [denied] (never ran) and [error] (ran but
///   failed on its own).
/// - [error]: tool ran but returned an error.
enum ToolCallPhase {
  preparing,
  awaitingApproval,
  running,
  done,
  denied,
  cancelled,
  error,
}

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
///
/// {@category Terminal & Rendering}
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
    final argsStr = args.entries.map((e) {
      final val = '${e.value}';
      final display = ansiTruncate(val, _inner - 6);
      if (e.key == 'path') {
        return '${e.key}: ${_linkPath(display)}';
      }
      return '${e.key}: $display';
    }).join(', ');
    return '$header\n    ${argsStr.styled.gray}';
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
      ToolCallPhase.preparing => ' \x1b[90m(preparing…)\x1b[0m',
      ToolCallPhase.awaitingApproval => ' \x1b[33m(awaiting approval)\x1b[0m',
      ToolCallPhase.running => ' \x1b[36m(running…)\x1b[0m',
      ToolCallPhase.done => '',
      ToolCallPhase.denied => ' \x1b[31m(denied)\x1b[0m',
      ToolCallPhase.cancelled => ' \x1b[90m(cancelled)\x1b[0m',
      ToolCallPhase.error => ' \x1b[31m(error)\x1b[0m',
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
    final headerText = '$icon Tool result';
    final header =
        ' ${success ? headerText.styled.bold.green : headerText.styled.bold.red}';
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
    final indented = linked.map((l) => '    ${l.styled.gray}').join('\n');
    return '$header\n$indented';
  }

  /// Render an error block.
  String renderError(String message) {
    final header = ' ${'✗ Error'.styled.bold.red}';
    final body =
        wrapIndented(message, _inner, firstPrefix: '    ', nextPrefix: '    ');
    // Apply red styling to each line
    final colored =
        body.split('\n').map((l) => l.styled.red.toString()).join('\n');
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
