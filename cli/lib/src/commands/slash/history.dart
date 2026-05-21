import 'package:glue_harness/glue_harness.dart';

import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/conversation/entry.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/ui/panel_modal.dart';
import 'package:glue/src/ui/responsive_table.dart';
import 'package:glue/src/ui/select_panel.dart';
import 'package:glue/src/ui/table_formatter.dart';

/// Renderable user-message entry surfaced in the `/history` picker.
class _HistoryEntry {
  const _HistoryEntry({required this.userMessageIndex, required this.text});

  final int userMessageIndex;
  final String text;
}

/// `/history` — browse user messages and fork the conversation.
class HistoryCommand extends SlashCommand {
  HistoryCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'history';

  @override
  String get description => 'Browse history or fork by index/query';

  @override
  String execute(List<String> args) {
    final entries = _collectEntries();
    if (args.isEmpty) {
      _openPicker(entries);
      return '';
    }
    return _resolveByQuery(args.join(' '), entries);
  }

  List<_HistoryEntry> _collectEntries() {
    final out = <_HistoryEntry>[];
    var userIndex = 0;
    for (final block in ctx.conversation.entries) {
      if (block.kind == EntryKind.user) {
        out.add(_HistoryEntry(userMessageIndex: userIndex, text: block.text));
        userIndex++;
      }
    }
    return out;
  }

  void _openPicker(List<_HistoryEntry> entries) {
    if (entries.isEmpty) {
      ctx.conversation.notify('No conversation history.');
      return;
    }

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

    final options = <SelectOption<_HistoryEntry>>[];
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

    final panel = SelectPanel<_HistoryEntry>(
      title: 'History',
      options: options,
      headerBuilder: table.renderHeader,
      searchHint: 'filter history',
      barrier: BarrierStyle.dim,
      width: PanelFluid(0.8, 40),
      height: PanelFluid(0.7, 10),
    );
    ctx.panels.push(panel);
    panel.selection.then((entry) {
      if (entry == null) {
        ctx.panels.dismiss(panel);
        return;
      }
      _openActionPanel(parentPanel: panel, entry: entry);
    });
  }

  void _openActionPanel({
    required SelectPanel<_HistoryEntry> parentPanel,
    required _HistoryEntry entry,
  }) {
    final actionPanel = PanelModal(
      title: 'Action',
      lines: const ['Fork conversation', 'Copy to clipboard'],
      barrier: BarrierStyle.dim,
      height: PanelFixed(4),
      width: PanelFixed(30),
      selectable: true,
    );
    ctx.panels.push(actionPanel);

    actionPanel.selection.then((idx) {
      ctx.panels.dismiss(actionPanel);
      ctx.panels.dismiss(parentPanel);
      if (idx == null) return;
      switch (idx) {
        case 0:
          _fork(entry.userMessageIndex, entry.text);
        case 1:
          copyToClipboard(entry.text).then((ok) {
            ctx.conversation.notify(
              ok
                  ? 'Copied to clipboard.'
                  : 'Clipboard copy failed on this platform.',
            );
          });
      }
    });
  }

  void _fork(int userMessageIndex, String messageText) {
    final result = ctx.session.forkSession(
      userMessageIndex: userMessageIndex,
      messageText: messageText,
      agent: ctx.agent,
    );
    if (result == null) return;
    ctx.conversation.resetForReplay();
    ctx.conversation.notify(result.message);
    ctx.conversation.appendReplayEntries(result.replay.entries);
    ctx.editor.setText(result.draftText);
  }

  String _resolveByQuery(String query, List<_HistoryEntry> entries) {
    final normalized = query.trim();
    if (normalized.isEmpty) return 'Usage: /history [index-or-query]';
    if (entries.isEmpty) return 'No conversation history.';

    final numeric = int.tryParse(normalized);
    if (numeric != null) {
      final position = numeric - 1; // UI is 1-based.
      if (position < 0 || position >= entries.length) {
        return 'History index out of range: $numeric (1-${entries.length}).';
      }
      final entry = entries[position];
      _fork(entry.userMessageIndex, entry.text);
      return '';
    }

    final needle = normalized.toLowerCase();
    final matches = entries
        .where((e) => e.text.toLowerCase().contains(needle))
        .toList();

    if (matches.isEmpty) {
      final preview = entries.take(5).toList();
      final lines = preview
          .asMap()
          .entries
          .map((e) {
            final idx = e.key + 1;
            final compact = e.value.text.replaceAll('\n', ' ').trim();
            final short = compact.length > 56
                ? '${compact.substring(0, 56)}…'
                : compact;
            return '  #$idx $short';
          })
          .join('\n');
      return 'No history entry matches "$normalized".\n'
          'Recent entries:\n'
          '${lines.isEmpty ? "  (none)" : lines}';
    }

    if (matches.length > 1) {
      final preview = matches
          .take(5)
          .map((entry) {
            final idx = entries.indexOf(entry) + 1;
            final compact = entry.text.replaceAll('\n', ' ').trim();
            final short = compact.length > 56
                ? '${compact.substring(0, 56)}…'
                : compact;
            return '  #$idx $short';
          })
          .join('\n');
      return 'Multiple history entries match "$normalized":\n'
          '$preview\n'
          'Use /history <index> for an exact fork point.';
    }

    final entry = matches.first;
    _fork(entry.userMessageIndex, entry.text);
    return '';
  }
}
