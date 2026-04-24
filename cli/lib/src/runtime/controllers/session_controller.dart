import 'dart:async';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/commands/arg_completers.dart' as arg_completers;
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/core/clipboard.dart';
import 'package:glue/src/runtime/commands/command_host.dart';
import 'package:glue/src/runtime/services/session.dart';
import 'package:glue/src/session/title_generator.dart';
import 'package:glue/src/storage/session_store.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/ui/components/panel.dart';
import 'package:glue/src/ui/components/tables.dart';
import 'package:glue/src/ui/services/panels.dart';
import 'package:glue/src/utils.dart';

/// A conversation-history entry eligible for fork/copy actions in the
/// `/history` panel. Built by the app layer (which owns the rendered block
/// list) and handed to [SessionController.openHistoryPanel].
class HistoryPanelEntry {
  final int userMessageIndex;
  final String text;

  const HistoryPanelEntry({
    required this.userMessageIndex,
    required this.text,
  });
}

class SessionController implements SessionCommandController {
  const SessionController({
    required this.session,
    required this.agent,
    required this.panels,
    required this.addSystemMessage,
    required this.render,
    required this.historyEntries,
    required this.shortenPath,
    required this.cwd,
    required this.modelLabel,
    required this.approvalLabel,
    required this.autoApprovedTools,
  });

  final Session session;
  final Agent agent;
  final Panels panels;
  final void Function(String message) addSystemMessage;
  final void Function() render;
  final List<HistoryPanelEntry> Function() historyEntries;
  final String Function(String path) shortenPath;
  final String cwd;
  final String Function() modelLabel;
  final String Function() approvalLabel;
  final List<String> Function() autoApprovedTools;

  @override
  String sessionAction(List<String> args) {
    final subcommand = args.isEmpty ? '' : args.first.toLowerCase();
    switch (subcommand) {
      case 'copy':
        final sessionId = session.currentId;
        if (sessionId == null) {
          return 'No active session yet — nothing to copy.';
        }
        unawaited(
          copyToClipboard(sessionId).then((ok) {
            addSystemMessage(
              ok
                  ? 'Session ID copied to clipboard.\n  $sessionId'
                  : 'Could not access clipboard. Session ID:\n  $sessionId',
            );
            render();
          }),
        );
        return '';
      case '':
        return _buildSessionInfo();
      default:
        return 'Unknown subcommand "$subcommand". Try: /session copy';
    }
  }

  String _buildSessionInfo() {
    final store = session.currentStore;
    final meta = store?.meta;
    final trustedList = autoApprovedTools()..sort();
    final startedAt = meta?.startTime;
    final startedLabel = startedAt == null
        ? '(not started)'
        : '${startedAt.toLocal().toIso8601String().substring(0, 19)} '
            '(${startedAt.timeAgo})';

    final buf = StringBuffer();
    buf.writeln('Session Info');
    buf.writeln('  Title:        ${meta?.title ?? "(untitled)"}');
    buf.writeln('  Session ID:   ${meta?.id ?? "(none)"}');
    buf.writeln('  Model:        ${modelLabel()}');
    buf.writeln('  Directory:    ${shortenPath(cwd)}');
    buf.writeln('  Started:      $startedLabel');
    buf.writeln('  Tokens used:  ${agent.tokenCount}');
    buf.writeln('  Messages:     ${agent.conversation.length}');
    buf.writeln('  Tools:        ${agent.tools.length} registered');
    buf.writeln('  Approval:     ${approvalLabel()} (Shift+Tab to toggle)');
    buf.writeln('  Auto-approve: ${trustedList.join(", ")}');
    return buf.toString();
  }

  @override
  void openHistoryPanel() {
    final entries = historyEntries();
    if (entries.isEmpty) {
      addSystemMessage('No conversation history.');
      render();
      return;
    }

    final panelWidth = PanelFluid(0.8, 40);
    final indexed = List<int>.generate(entries.length, (i) => i);
    final table = ResponsiveTable<int>(
      columns: const [
        TableColumn(
          key: 'idx',
          header: '#',
          align: TableAlign.right,
          maxWidth: 4,
        ),
        TableColumn(key: 'text', header: 'MESSAGE', minWidth: 16),
      ],
      rows: indexed,
      gap: ' ',
      includeHeaderInWidth: true,
      getValues: (i) => {
        'idx': (i + 1).toString().padLeft(3).styled.dim.toString(),
        'text': entries[i].text.replaceAll('\n', ' '),
      },
    );

    final options = <SelectOption<HistoryPanelEntry>>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final text = entry.text.replaceAll('\n', ' ');
      options.add(
        SelectOption.responsive(
          value: entry,
          build: (w) => table.renderRow(i, w),
          searchText: '$i $text',
        ),
      );
    }

    final panel = SelectPanel<HistoryPanelEntry>(
      title: 'History',
      options: options,
      headerBuilder: table.renderHeader,
      searchHint: 'filter history',
      barrier: BarrierStyle.dim,
      width: panelWidth,
      height: PanelFluid(0.7, 10),
    );
    panels.push(panel);

    panel.selection.then((entry) {
      if (entry == null) {
        panels.remove(panel);
        return;
      }
      _openHistoryActionPanel(parentPanel: panel, entry: entry);
    });
  }

  void _openHistoryActionPanel({
    required SelectPanel<HistoryPanelEntry> parentPanel,
    required HistoryPanelEntry entry,
  }) {
    final panel = Panel(
      title: 'Action',
      lines: ['Fork conversation', 'Copy to clipboard'],
      barrier: BarrierStyle.dim,
      height: PanelFixed(4),
      width: PanelFixed(30),
      selectable: true,
    );
    panels.push(panel);

    panel.selection.then((idx) {
      panels.remove(panel);
      panels.remove(parentPanel);
      if (idx == null) {
        render();
        return;
      }
      switch (idx) {
        case 0:
          if (session.fork(entry.userMessageIndex, entry.text)) render();
        case 1:
          unawaited(() async {
            final copied = await copyToClipboard(entry.text);
            addSystemMessage(
              copied
                  ? 'Copied to clipboard.'
                  : 'Clipboard copy failed on this platform.',
            );
            render();
          }());
      }
    });
  }

  @override
  void openResumePanel() {
    final sessions = session.list();
    if (sessions.isEmpty) {
      addSystemMessage('No saved sessions found.');
      render();
      return;
    }

    final panelWidth = PanelFluid(0.8, 40);

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
        final displayId = s.title ?? s.id;
        return {
          'fork': s.forkedFrom != null ? '[F]'.styled.cyan.toString() : '',
          'id': displayId.styled.cyan.toString(),
          'model': s.modelRef,
          'messages': s.messageCount.toString(),
          'dir': shortenPath(s.cwd).styled.dim.toString(),
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
      width: panelWidth,
      height: PanelFluid(0.7, 10),
    );
    panels.push(panel);

    panel.selection.then((meta) {
      panels.remove(panel);
      if (meta == null) return;
      final result = session.resume(meta);
      if (result.isNotEmpty) addSystemMessage(result);
      render();
    });
  }

  @override
  String historyActionByQuery(String query) {
    final normalized = query.trim();
    if (normalized.isEmpty) return 'Usage: /history [index-or-query]';

    final entries = historyEntries();
    if (entries.isEmpty) return 'No conversation history.';

    final numeric = int.tryParse(normalized);
    if (numeric != null) {
      final position = numeric - 1;
      if (position < 0 || position >= entries.length) {
        return 'History index out of range: $numeric (1-${entries.length}).';
      }
      final entry = entries[position];
      if (session.fork(entry.userMessageIndex, entry.text)) render();
      return '';
    }

    final needle = normalized.toLowerCase();
    final matches = entries
        .where((entry) => entry.text.toLowerCase().contains(needle))
        .toList();

    if (matches.isEmpty) {
      final preview = entries.take(5).toList();
      final lines = preview.asMap().entries.map((e) {
        final idx = e.key + 1;
        final compact = e.value.text.replaceAll('\n', ' ').trim();
        final short =
            compact.length > 56 ? '${compact.substring(0, 56)}…' : compact;
        return '  #$idx $short';
      }).join('\n');
      return 'No history entry matches "$normalized".\n'
          'Recent entries:\n'
          '${lines.isEmpty ? "  (none)" : lines}';
    }

    if (matches.length > 1) {
      final preview = matches.take(5).map((entry) {
        final idx = entries.indexOf(entry) + 1;
        final compact = entry.text.replaceAll('\n', ' ').trim();
        final short =
            compact.length > 56 ? '${compact.substring(0, 56)}…' : compact;
        return '  #$idx $short';
      }).join('\n');
      return 'Multiple history entries match "$normalized":\n'
          '$preview\n'
          'Use /history <index> for an exact fork point.';
    }

    final entry = matches.first;
    if (session.fork(entry.userMessageIndex, entry.text)) render();
    return '';
  }

  @override
  String resumeSessionByQuery(String query) {
    final normalized = query.trim();
    if (normalized.isEmpty) return 'Usage: /resume [session-id-or-query]';

    final sessions = session.list();
    if (sessions.isEmpty) return 'No saved sessions found.';

    final exactId = sessions.where((s) => s.id == normalized).toList();
    if (exactId.length == 1) {
      return session.resume(exactId.first);
    }

    final needle = normalized.toLowerCase();
    final matches = sessions.where((s) {
      final title = (s.title ?? '').toLowerCase();
      final entryCwd = s.cwd.toLowerCase();
      return s.id.toLowerCase().contains(needle) ||
          title.contains(needle) ||
          entryCwd.contains(needle);
    }).toList();

    if (matches.isEmpty) {
      final recent = sessions.take(5).map((s) => s.id).join(', ');
      return 'No session matches "$normalized". '
          'Try a session ID from: ${recent.isEmpty ? "(none)" : recent}';
    }

    if (matches.length > 1) {
      final preview = matches.take(5).map((s) {
        final title = (s.title ?? '').trim();
        return title.isEmpty ? '  - ${s.id}' : '  - ${s.id} ($title)';
      }).join('\n');
      return 'Multiple sessions match "$normalized":\n'
          '$preview\n'
          'Use a more specific session ID.';
    }

    return session.resume(matches.first);
  }

  @override
  String renameSession(String title) {
    final normalized = TitleGenerator.sanitize(title)?.trim();
    if (normalized == null || normalized.isEmpty) {
      return 'Usage: /rename <new title>';
    }
    session.ensureStore();
    unawaited(session.rename(normalized));
    return 'Renamed session to "$normalized".';
  }

  @override
  List<SlashArgCandidate> sessionArgCandidates(
    List<String> prior,
    String partial,
  ) {
    return arg_completers.sessionArgCandidates(prior, partial);
  }

}
