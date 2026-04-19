import 'dart:async';
import 'dart:io';

import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/credentials/credential_store.dart';
import 'package:glue/src/providers/auth_flow.dart';
import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/storage/session_store.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/ui/api_key_prompt_panel.dart';
import 'package:glue/src/ui/device_code_panel.dart';
import 'package:glue/src/ui/model_panel_formatter.dart';
import 'package:glue/src/ui/panel_modal.dart';
import 'package:glue/src/ui/select_panel.dart';
import 'package:glue/src/ui/table_formatter.dart';

class HistoryPanelEntry {
  final int userMessageIndex;
  final String text;

  const HistoryPanelEntry({
    required this.userMessageIndex,
    required this.text,
  });
}

/// Handles panel modal flows for help, resume, and history.
class PanelController {
  final List<PanelOverlay> _panelStack;
  final void Function() _render;
  final int Function() _terminalWidth;

  PanelController({
    required List<PanelOverlay> panelStack,
    required void Function() render,
    int Function()? terminalWidth,
  })  : _panelStack = panelStack,
        _render = render,
        _terminalWidth = terminalWidth ?? _defaultTerminalWidth;

  void openHelp({
    required List<SlashCommand> commands,
  }) {
    final lines = <String>[];

    lines.add('${'■ COMMANDS'.styled.cyan}');
    lines.add('');
    for (final cmd in commands) {
      final aliases = cmd.aliases.isNotEmpty
          ? ' ${'(${cmd.aliases.map((a) => '/$a').join(', ')})'.styled.gray}'
          : '';
      final name = '/${cmd.name}'.padRight(16);
      lines.add('  ${name.styled.cyan}${cmd.description}$aliases');
    }

    lines.add('');
    lines.add('${'■ KEYBINDINGS'.styled.cyan}');
    lines.add('');
    lines.add('  ${'Ctrl+C'.padRight(16)}Cancel / Exit');
    lines.add('  ${'Escape'.padRight(16)}Cancel generation');
    lines.add('  ${'Up / Down'.padRight(16)}History navigation');
    lines.add('  ${'Ctrl+U'.padRight(16)}Clear line');
    lines.add('  ${'Ctrl+W'.padRight(16)}Delete word');
    lines.add('  ${'Ctrl+A / E'.padRight(16)}Start / End of line');
    lines.add('  ${'PageUp / Dn'.padRight(16)}Scroll output');
    lines.add('  ${'Tab'.padRight(16)}Accept completion');

    lines.add('');
    lines.add('${'■ PERMISSIONS'.styled.cyan}');
    lines.add('');
    lines.add('  ${'Shift+Tab'.padRight(16)}Cycle tool approval mode');
    lines.add('  ${'/info'.padRight(16)}View current mode');

    lines.add('');
    lines.add('${'■ FILE REFERENCES'.styled.cyan}');
    lines.add('');
    lines.add('  ${'@path/to/file'.padRight(16)}Attach file to message');
    lines.add('  ${'@dir/'.padRight(16)}Browse directory');

    final panel = PanelModal(
      title: 'HELP',
      lines: lines,
      barrier: BarrierStyle.dim,
      height: PanelFluid(0.5, 10),
    );
    _panelStack.add(panel);
    _render();

    panel.result.then((_) {
      _panelStack.remove(panel);
      _render();
    });
  }

  void openResume({
    required List<SessionMeta> sessions,
    required String Function(DateTime) timeAgo,
    required String Function(String path) shortenPath,
    required String Function(SessionMeta session) onResume,
    required void Function(String message) addSystemMessage,
  }) {
    if (sessions.isEmpty) {
      addSystemMessage('No saved sessions found.');
      _render();
      return;
    }

    final panelWidth = PanelFluid(0.7, 40);
    final contentWidth = _contentWidthFor(panelWidth);
    final rows = <Map<String, String>>[];
    final options = <SelectOption<SessionMeta>>[];
    for (var i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      final ago = timeAgo(s.startTime);
      final shortCwd = shortenPath(s.cwd);
      final displayId = s.title ?? s.id;
      rows.add({
        'fork': s.forkedFrom != null ? '[F]'.styled.cyan.toString() : '',
        'id': displayId.styled.cyan.toString(),
        'model': s.modelRef,
        'dir': shortCwd.styled.dim.toString(),
        'age': ago.styled.dim.toString(),
      });
      options.add(SelectOption(
        value: s,
        label: '',
        searchText: '$displayId ${s.modelRef} ${s.cwd} ${s.forkedFrom ?? ''}',
      ));
    }

    final table = TableFormatter.format(
      columns: const [
        TableColumn(key: 'fork', header: 'FORK', maxWidth: 4),
        TableColumn(key: 'id', header: 'ID', maxWidth: 24),
        TableColumn(key: 'model', header: 'MODEL', maxWidth: 22),
        TableColumn(key: 'dir', header: 'DIRECTORY', maxWidth: 36),
        TableColumn(
          key: 'age',
          header: 'AGE',
          align: TableAlign.right,
          maxWidth: 10,
        ),
      ],
      rows: rows,
      gap: ' ',
      maxTotalWidth: contentWidth,
      includeHeader: true,
      includeHeaderInWidth: true,
    );
    for (var i = 0; i < options.length; i++) {
      options[i] = SelectOption(
        value: options[i].value,
        label: table.rowLines[i],
        searchText: options[i].searchText,
      );
    }

    final panel = SelectPanel<SessionMeta>(
      title: 'Resume Session',
      options: options,
      headerLines: table.headerLines,
      searchHint: 'filter sessions',
      emptyText: 'No matching sessions.',
      barrier: BarrierStyle.dim,
      width: panelWidth,
      height: PanelFluid(0.6, 12),
    );
    _panelStack.add(panel);
    _render();

    panel.selection.then((session) {
      _panelStack.remove(panel);
      if (session == null) {
        _render();
        return;
      }
      final result = onResume(session);
      if (result.isNotEmpty) {
        addSystemMessage(result);
      }
      _render();
    });
  }

  void openHistory({
    required List<HistoryPanelEntry> entries,
    required void Function(int userMessageIndex, String messageText) onFork,
    required void Function(String message) addSystemMessage,
  }) {
    if (entries.isEmpty) {
      addSystemMessage('No conversation history.');
      _render();
      return;
    }

    final panelWidth = PanelFluid(0.7, 40);
    final contentWidth = _contentWidthFor(panelWidth);
    final historyRows = <Map<String, String>>[];
    final options = <SelectOption<HistoryPanelEntry>>[];
    for (var i = 0; i < entries.length; i++) {
      final text = entries[i].text.replaceAll('\n', ' ');
      historyRows.add({
        'idx': (i + 1).toString().padLeft(3).styled.dim.toString(),
        'text': text,
      });
      options.add(SelectOption(
        value: entries[i],
        label: '',
        searchText: '$i $text',
      ));
    }
    final table = TableFormatter.format(
      columns: const [
        TableColumn(
            key: 'idx', header: '#', align: TableAlign.right, maxWidth: 4),
        TableColumn(key: 'text', header: 'MESSAGE', minWidth: 16),
      ],
      rows: historyRows,
      gap: ' ',
      maxTotalWidth: contentWidth,
      includeHeader: true,
      includeHeaderInWidth: true,
    );
    for (var i = 0; i < options.length; i++) {
      options[i] = SelectOption(
        value: options[i].value,
        label: table.rowLines[i],
        searchText: options[i].searchText,
      );
    }

    final panel = SelectPanel<HistoryPanelEntry>(
      title: 'History',
      options: options,
      headerLines: table.headerLines,
      searchHint: 'filter history',
      barrier: BarrierStyle.dim,
      width: panelWidth,
      height: PanelFluid(0.6, 12),
    );
    _panelStack.add(panel);
    _render();

    panel.selection.then((entry) {
      if (entry == null) {
        _panelStack.remove(panel);
        _render();
        return;
      }

      _openHistoryActionPanel(
        parentPanel: panel,
        entry: entry,
        onFork: onFork,
        addSystemMessage: addSystemMessage,
      );
    });
  }

  Future<void> openModel({
    required GlueConfig config,
    required ModelRef currentRef,
    required String Function(CatalogRow entry) onModelSelected,
    required void Function(String message) addSystemMessage,
    required bool Function() isSelectionEnabled,
  }) async {
    // Show models that are tool-capable AND whose provider has credentials.
    final defaultCaps = <String>{Capability.chat, Capability.tools};
    final entries = flattenCatalog(
      config.catalogData,
      where: (p) =>
          config.credentials.health(p) == CredentialHealth.ok ||
          p.auth.kind == AuthKind.none,
    ).where((row) => row.model.capabilities.containsAll(defaultCaps)).toList();

    if (entries.isEmpty) {
      addSystemMessage(
        'No models available. Run `/provider add <id>` to connect one.',
      );
      _render();
      return;
    }

    final panelWidth = PanelFluid(0.7, 40);
    final contentWidth = _contentWidthFor(panelWidth);
    final formatted = formatModelPanelLines(
      entries,
      currentRef: currentRef,
      maxTotalWidth: contentWidth,
    );
    final options = <SelectOption<CatalogRow>>[];
    for (var i = 0; i < formatted.entries.length; i++) {
      options.add(
        SelectOption(
          value: formatted.entries[i],
          label: formatted.lines[i],
          searchText: stripAnsi(formatted.lines[i]),
        ),
      );
    }

    final panel = SelectPanel<CatalogRow>(
      title: 'Switch Model',
      options: options,
      headerLines: formatted.headerLines,
      searchHint: 'filter models',
      barrier: BarrierStyle.dim,
      width: panelWidth,
      height: PanelFluid(0.6, 12),
      initialIndex: formatted.initialIndex,
    );
    _panelStack.add(panel);
    _render();

    unawaited(panel.selection.then((entry) {
      _panelStack.remove(panel);
      if (entry == null) {
        _render();
        return;
      }
      if (!isSelectionEnabled()) {
        _render();
        return;
      }
      final result = onModelSelected(entry);
      addSystemMessage(result);
      _render();
    }));
  }

  /// Open the `/provider add` flow. Picks a provider (if [providerId] is
  /// null), then dispatches to [ApiKeyPromptPanel] or [DeviceCodePanel]
  /// based on the provider's [AuthKind].
  Future<void> openProviderAdd({
    required GlueConfig config,
    required String? providerId,
    required void Function(String message) addSystemMessage,
  }) async {
    ProviderDef? provider;
    if (providerId != null) {
      provider = config.catalogData.providers[providerId];
      if (provider == null) {
        addSystemMessage(
          'Unknown provider "$providerId". Try `/provider list`.',
        );
        _render();
        return;
      }
    } else {
      provider = await _pickProvider(config);
      if (provider == null) {
        _render();
        return;
      }
    }

    if (provider.auth.kind == AuthKind.none) {
      addSystemMessage('${provider.name} needs no credentials.');
      _render();
      return;
    }

    final adapter = config.adapters.lookup(provider.adapter);
    if (adapter == null) {
      addSystemMessage(
        'No adapter for wire protocol "${provider.adapter}".',
      );
      _render();
      return;
    }

    final flow = await adapter.beginInteractiveAuth(
      provider: provider,
      store: config.credentials,
    );
    if (flow == null) {
      addSystemMessage('${provider.name} needs no interactive setup.');
      _render();
      return;
    }

    switch (flow) {
      case ApiKeyFlow():
        await _runApiKeyFlow(
          config: config,
          provider: provider,
          flow: flow,
          addSystemMessage: addSystemMessage,
        );
      case DeviceCodeFlow():
        await _runDeviceCodeFlow(
          provider: provider,
          flow: flow,
          addSystemMessage: addSystemMessage,
        );
      case PkceFlow():
        addSystemMessage(
          'PKCE OAuth is not implemented yet for ${provider.name}.',
        );
        _render();
    }
  }

  Future<ProviderDef?> _pickProvider(GlueConfig config) async {
    final providers = config.catalogData.providers.values
        .where((p) => p.enabled && p.auth.kind != AuthKind.none)
        .toList();

    final options = <SelectOption<ProviderDef>>[];
    for (final p in providers) {
      final status = _statusLabel(p, config);
      final line = '${p.name.padRight(16)}  ${p.id.styled.dim}   '
          '${status.styled.dim}';
      options.add(
        SelectOption<ProviderDef>(
          value: p,
          label: line,
          searchText: '${p.id} ${p.name}',
        ),
      );
    }

    final panel = SelectPanel<ProviderDef>(
      title: 'Add provider',
      options: options,
      searchHint: 'filter providers',
      width: PanelFluid(0.6, 48),
      height: PanelFluid(0.5, 10),
    );
    _panelStack.add(panel);
    _render();
    final picked = await panel.selection;
    _panelStack.remove(panel);
    return picked;
  }

  Future<void> _runApiKeyFlow({
    required GlueConfig config,
    required ProviderDef provider,
    required ApiKeyFlow flow,
    required void Function(String) addSystemMessage,
  }) async {
    final panel = ApiKeyPromptPanel(
      providerId: flow.providerId,
      providerName: flow.providerName,
      envVar: flow.envVar,
      envPresent: flow.envPresent,
      helpUrl: flow.helpUrl,
    );
    _panelStack.add(panel);
    _render();
    final value = await panel.result;
    _panelStack.remove(panel);

    if (value == null) {
      addSystemMessage('Cancelled.');
      _render();
      return;
    }
    if (value.isEmpty && flow.envPresent != null) {
      addSystemMessage(
        'Keeping env var \$${flow.envVar}. ${provider.name} connected.',
      );
      _render();
      return;
    }

    config.credentials.setFields(provider.id, {'api_key': value});
    addSystemMessage('Connected to ${provider.name}.');
    _render();
  }

  Future<void> _runDeviceCodeFlow({
    required ProviderDef provider,
    required DeviceCodeFlow flow,
    required void Function(String) addSystemMessage,
  }) async {
    final panel = DeviceCodePanel(flow: flow);
    _panelStack.add(panel);
    _render();
    final fields = await panel.result;
    _panelStack.remove(panel);

    if (fields == null) {
      addSystemMessage('${provider.name} connection cancelled.');
    } else {
      addSystemMessage('Connected to ${provider.name}.');
    }
    _render();
  }

  String _statusLabel(ProviderDef p, GlueConfig config) {
    if (p.auth.kind == AuthKind.none) return 'no auth';
    final adapter = config.adapters.lookup(p.adapter);
    if (adapter != null && adapter.isConnected(p, config.credentials)) {
      return 'connected';
    }
    return 'missing';
  }

  void _openHistoryActionPanel({
    required SelectPanel<HistoryPanelEntry> parentPanel,
    required HistoryPanelEntry entry,
    required void Function(int userMessageIndex, String messageText) onFork,
    required void Function(String message) addSystemMessage,
  }) {
    final panel = PanelModal(
      title: 'Action',
      lines: ['Fork conversation', 'Copy to clipboard'],
      barrier: BarrierStyle.dim,
      height: PanelFixed(4),
      width: PanelFixed(30),
      selectable: true,
    );
    _panelStack.add(panel);
    _render();

    panel.selection.then((idx) {
      _panelStack.remove(panel);
      _panelStack.remove(parentPanel);
      if (idx == null) {
        _render();
        return;
      }
      switch (idx) {
        case 0:
          onFork(entry.userMessageIndex, entry.text);
        case 1:
          unawaited(() async {
            final copied = await _copyToClipboard(entry.text);
            addSystemMessage(
              copied
                  ? 'Copied to clipboard.'
                  : 'Clipboard copy failed on this platform.',
            );
            _render();
          }());
      }
    });
  }

  Future<bool> _copyToClipboard(String text) async {
    final commands = _clipboardCommands();
    for (final command in commands) {
      try {
        final process = await Process.start(command.$1, command.$2);
        process.stdin.write(text);
        await process.stdin.close();
        final exitCode = await process.exitCode;
        if (exitCode == 0) return true;
      } catch (_) {
        // Try next clipboard command fallback.
      }
    }
    return false;
  }

  List<(String, List<String>)> _clipboardCommands() {
    if (Platform.isMacOS) {
      return [('pbcopy', const [])];
    }
    if (Platform.isWindows) {
      return [('clip', const [])];
    }
    if (Platform.isLinux) {
      return [
        ('wl-copy', const []),
        ('xclip', const ['-selection', 'clipboard']),
        ('xsel', const ['--clipboard', '--input']),
      ];
    }
    return const [];
  }

  int _contentWidthFor(PanelSize panelWidth) {
    final resolvedWidth = panelWidth.resolve(_terminalWidth());
    return resolvedWidth > 4 ? resolvedWidth - 4 : 1;
  }

  static int _defaultTerminalWidth() => 120;
}
