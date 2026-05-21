import 'package:glue_harness/glue_harness.dart';

import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/extensions/time_ago.dart';
import 'package:glue/src/extensions/token_format.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/ui/panel_modal.dart';
import 'package:glue/src/ui/responsive_table.dart';
import 'package:glue/src/ui/select_panel.dart';
import 'package:glue/src/ui/table_formatter.dart';

/// `/resume` — open a saved-session picker, or resume by id/query.
class ResumeCommand extends SlashCommand {
  ResumeCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'resume';

  @override
  String get description => 'Resume a session (panel or by ID/query)';

  @override
  String execute(List<String> args) {
    if (args.isEmpty) {
      _openPicker();
      return '';
    }
    return _resolveByQuery(args.join(' '));
  }

  void _openPicker() {
    final sessions = ctx.session.listSessions();
    if (sessions.isEmpty) {
      ctx.conversation.notify('No saved sessions found.');
      return;
    }

    final table = ResponsiveTable<SessionMeta>(
      columns: const [
        TableColumn(key: 'fork', header: 'FORK', minWidth: 4),
        TableColumn(key: 'id', header: 'ID', minWidth: 8),
        TableColumn(key: 'model', header: 'MODEL', minWidth: 10),
        TableColumn(
          key: 'messages',
          header: 'MSGS',
          minWidth: 6,
          align: TableAlign.right,
        ),
        TableColumn(key: 'dir', header: 'DIRECTORY', minWidth: 15),
        TableColumn(
          key: 'age',
          header: 'AGE',
          align: TableAlign.right,
          minWidth: 6,
        ),
      ],
      rows: sessions,
      gap: ' ',
      includeHeaderInWidth: true,
      getValues: (s) {
        final displayId = s.title ?? s.id.value;
        return {
          'fork': s.forkedFrom != null ? '[F]'.styled.cyan.toString() : '',
          'id': displayId.styled.cyan.toString(),
          'model': s.modelRef,
          'messages': s.messageCount.toString(),
          'dir': ctx.environment.shortenPath(s.cwd).styled.dim.toString(),
          'age': s.startTime.timeAgo.styled.dim.toString(),
        };
      },
    );

    final options = <SelectOption<SessionMeta>>[];
    for (var i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      final displayId = s.title ?? s.id;
      options.add(
        SelectOption.responsive(
          value: s,
          build: (w) => table.renderRow(i, w),
          searchText: '$displayId ${s.modelRef} ${s.cwd} ${s.forkedFrom ?? ''}',
        ),
      );
    }

    final panel = SelectPanel<SessionMeta>(
      title: 'Resume Session',
      options: options,
      headerBuilder: table.renderHeader,
      searchHint: 'filter sessions',
      emptyText: 'No matching sessions.',
      barrier: BarrierStyle.dim,
      width: PanelFluid(0.8, 40),
      height: PanelFluid(0.7, 10),
    );
    ctx.panels.push(panel);
    panel.selection.then((session) {
      ctx.panels.dismiss(panel);
      if (session == null) return;
      final result = _resume(session);
      if (result.isNotEmpty) ctx.conversation.notify(result);
    });
  }

  String _resolveByQuery(String query) {
    final normalized = query.trim();
    if (normalized.isEmpty) return 'Usage: /resume [session-id-or-query]';

    final sessions = ctx.session.listSessions();
    if (sessions.isEmpty) return 'No saved sessions found.';

    final exactId = sessions.where((s) => s.id.value == normalized).toList();
    if (exactId.length == 1) return _resume(exactId.first);

    final needle = normalized.toLowerCase();
    final matches = sessions.where((s) {
      final title = (s.title ?? '').toLowerCase();
      final cwd = s.cwd.toLowerCase();
      return s.id.value.toLowerCase().contains(needle) ||
          title.contains(needle) ||
          cwd.contains(needle);
    }).toList();

    if (matches.isEmpty) {
      final recent = sessions.take(5).map((s) => s.id).join(', ');
      return 'No session matches "$normalized". '
          'Try a session ID from: ${recent.isEmpty ? "(none)" : recent}';
    }

    if (matches.length > 1) {
      final preview = matches
          .take(5)
          .map((s) {
            final title = (s.title ?? '').trim();
            return title.isEmpty ? '  - ${s.id}' : '  - ${s.id} ($title)';
          })
          .join('\n');
      return 'Multiple sessions match "$normalized":\n'
          '$preview\n'
          'Use a more specific session ID.';
    }

    return _resume(matches.first);
  }

  /// Resume [meta] into the live app. Composes session-state mutation,
  /// transcript reset, replay, and optional title backfill via [ctx]
  /// primitives. Returns the user-visible result message.
  String _resume(SessionMeta meta) {
    final result = ctx.session.resumeSession(session: meta, agent: ctx.agent);
    ctx.conversation.resetForReplay();
    ctx.session
      ..titleInitialRequested = meta.title != null
      ..titleReevaluationRequested =
          meta.titleState == SessionTitleState.stable ||
          meta.titleGenerationCount >= 2
      ..titleManuallyOverridden = meta.titleSource == SessionTitleSource.user;

    ctx.conversation.notify(
      'Resuming session ${meta.id} '
      '(${meta.modelRef}, ${meta.startTime.timeAgo})',
    );

    if (!result.hasConversation) {
      return 'Session ${meta.id} has no conversation data.';
    }

    // Carry-over summary surfaces cost continuity instead of pretending the
    // counter restarts at zero. Skipped on Ollama / pre-recordUsage sessions
    // where no usage rows were ever persisted.
    final usage = result.replay.totalUsage;
    if (usage.totalCalls > 0) {
      final summary = StringBuffer(
        'Carry-over: ${formatCompactTokens(usage.totalTokens)} tokens '
        'over ${usage.totalCalls} call${usage.totalCalls == 1 ? '' : 's'}',
      );
      final hit = usage.cacheHitRate;
      if (hit != null &&
          (usage.totalCacheRead > 0 || usage.totalCacheWrite > 0)) {
        summary.write(' · ${(hit * 100).toStringAsFixed(0)}% cached');
      }
      summary.write('. Run /usage for the per-role breakdown.');
      ctx.conversation.notify(summary.toString());
    }

    ctx.conversation.appendReplayEntries(result.replay.entries);

    final firstUserMessage = result.replay.firstUserMessage;
    if (!ctx.session.titleInitialRequested &&
        !ctx.session.titleManuallyOverridden &&
        firstUserMessage != null &&
        firstUserMessage.isNotEmpty) {
      ctx.session.titleInitialRequested = true;
      ctx.backfillTitle(firstUserMessage);
    }

    return result.message;
  }
}
