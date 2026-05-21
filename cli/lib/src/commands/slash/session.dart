import 'package:glue_harness/glue_harness.dart';

import 'package:glue/src/app/model_display.dart';
import 'package:glue/src/commands/arg_completers.dart' as arg_completers;
import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/extensions/time_ago.dart';

/// `/session` — show current session info, or copy the session ID.
class SessionCommand extends SlashCommand {
  SessionCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'session';

  @override
  String get description =>
      'Show current session info, or /session copy to copy ID';

  @override
  SlashArgCompleter? get argCompleter => arg_completers.sessionArgCandidates;

  @override
  String execute(List<String> args) {
    final subcommand = args.isEmpty ? '' : args.first.toLowerCase();
    switch (subcommand) {
      case '':
        return _buildInfo();
      case 'copy':
        return _copyId();
      default:
        return 'Unknown subcommand "$subcommand". Try: /session copy';
    }
  }

  String _copyId() {
    final id = ctx.session.currentSessionId;
    if (id == null) return 'No active session yet — nothing to copy.';
    copyToClipboard(id.value).then((ok) {
      ctx.conversation.notify(
        ok
            ? 'Session ID copied to clipboard.\n  ${id.value}'
            : 'Could not access clipboard. Session ID:\n  $id',
      );
    });
    return '';
  }

  String _buildInfo() {
    final store = ctx.session.currentStore;
    final meta = store?.meta;
    final shortCwd = ctx.environment.shortenPath(ctx.cwd);
    final trusted = ctx.autoApprovedTools.toList()..sort();
    final config = ctx.config;
    final displayModel = formatInfoModelLabel(
      config?.activeModel,
      config?.catalogData,
      ctx.modelId,
    );
    final startedAt = meta?.startTime;
    final startedLabel = startedAt == null
        ? '(not started)'
        : '${startedAt.toLocal().toIso8601String().substring(0, 19)} '
              '(${startedAt.timeAgo})';

    final buf = StringBuffer()
      ..writeln('Session Info')
      ..writeln('  Title:        ${meta?.title ?? "(untitled)"}')
      ..writeln('  Session ID:   ${meta?.id ?? "(none)"}')
      ..writeln('  Model:        $displayModel')
      ..writeln('  Directory:    $shortCwd')
      ..writeln('  Started:      $startedLabel')
      ..writeln('  Tokens used:  ${ctx.agent.stats.totalTokens}')
      ..writeln('  Messages:     ${ctx.agent.conversation.length}')
      ..writeln('  Tools:        ${ctx.agent.tools.length} registered')
      ..writeln(
        '  Approval:     ${ctx.approval.mode.label} '
        '(Shift+Tab to toggle)',
      )
      ..writeln('  Auto-approve: ${trusted.join(", ")}');
    // Phase 3: surface cloud runtime info when present so the user
    // knows where the patch is going to land.
    if (meta?.runtimeId != null && meta!.runtimeId != 'host') {
      buf
        ..writeln('  Runtime:      ${meta.runtimeId}')
        ..writeln('  Sandbox:      ${meta.sandboxId ?? "(unknown)"}')
        ..writeln(
          '  Patch on close: '
          '~/.glue/sessions/${meta.id.value}/runtime.mbox',
        );
    }
    return buf.toString();
  }
}
