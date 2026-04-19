import 'dart:async';

import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/core/clipboard.dart' as shared_clipboard;
import 'package:glue/src/providers/auth_flow.dart';
import 'package:glue/src/providers/provider_adapter.dart';
import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/storage/session_store.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/ui/api_key_prompt_panel.dart';
import 'package:glue/src/ui/device_code_panel.dart';
import 'package:glue/src/ui/model_panel_formatter.dart';
import 'package:glue/src/ui/panel_modal.dart';
import 'package:glue/src/ui/responsive_table.dart';
import 'package:glue/src/ui/select_panel.dart';
import 'package:glue/src/ui/table_formatter.dart';

/// Actions offered on a selected provider in `/provider`'s action submenu.
/// Public so the list-builder ([providerActionsFor]) can be unit-tested.
enum ProviderAction {
  connect('Connect'),
  disconnect('Disconnect'),
  test('Test');

  const ProviderAction(this.label);
  final String label;
}

/// Decide which actions `_openProviderActionPanel` should show for a given
/// provider, given its state.
///
/// - Local providers (auth: none) can only be tested — there's nothing to
///   connect to or disconnect from.
/// - Remote providers show Connect-or-Disconnect depending on state, plus
///   Test.
List<ProviderAction> providerActionsFor({
  required bool connected,
  required bool isLocal,
}) {
  if (isLocal) return const [ProviderAction.test];
  return [
    connected ? ProviderAction.disconnect : ProviderAction.connect,
    ProviderAction.test,
  ];
}

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

  PanelController({
    required List<PanelOverlay> panelStack,
    required void Function() render,
  })  : _panelStack = panelStack,
        _render = render;

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

    final panelWidth = PanelFluid(0.8, 40);

    final table = ResponsiveTable<SessionMeta>(
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
      rows: sessions,
      gap: ' ',
      includeHeaderInWidth: true,
      getValues: (s) {
        final displayId = s.title ?? s.id;
        return {
          'fork': s.forkedFrom != null ? '[F]'.styled.cyan.toString() : '',
          'id': displayId.styled.cyan.toString(),
          'model': s.modelRef,
          'dir': shortenPath(s.cwd).styled.dim.toString(),
          'age': timeAgo(s.startTime).styled.dim.toString(),
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
      where: (p) {
        final adapter = config.adapters.lookup(p.adapter);
        return adapter != null && adapter.isConnected(p, config.credentials);
      },
    ).where((row) => row.model.capabilities.containsAll(defaultCaps)).toList();

    if (entries.isEmpty) {
      addSystemMessage(
        'No models available. Run `/provider add <id>` to connect one.',
      );
      _render();
      return;
    }

    final panelWidth = PanelFluid(0.8, 30);
    final builder = buildModelPanel(entries, currentRef: currentRef);

    final options = <SelectOption<CatalogRow>>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final searchText = stripAnsi(
        '${entry.providerName} ${entry.model.name} '
        '${entry.model.notes ?? ''}',
      );
      options.add(
        SelectOption.responsive(
          value: entry,
          build: (w) => builder.renderRow(i, w),
          searchText: searchText,
        ),
      );
    }

    final panel = SelectPanel<CatalogRow>(
      title: 'Switch Model',
      options: options,
      headerBuilder: builder.renderHeader,
      searchHint: 'filter models',
      barrier: BarrierStyle.dim,
      width: panelWidth,
      height: PanelFluid(0.7, 10),
      initialIndex: builder.initialIndex,
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

    if (providers.isEmpty) return null;

    final table = _buildProviderTable(providers, config);

    final options = <SelectOption<ProviderDef>>[];
    for (var i = 0; i < providers.length; i++) {
      final p = providers[i];
      options.add(
        SelectOption.responsive(
          value: p,
          build: (w) => table.renderRow(i, w),
          searchText: '${p.id} ${p.name}',
        ),
      );
    }

    final panel = SelectPanel<ProviderDef>(
      title: 'Add provider',
      options: options,
      headerBuilder: table.renderHeader,
      searchHint: 'filter providers',
      width: PanelFluid(0.7, 40),
      height: PanelFluid(0.6, 10),
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
    final panel = DeviceCodePanel(flow: flow, onNeedsRender: _render);
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

  /// Width-aware table shared by `_pickProvider` (`/provider add`) and
  /// `openProviderPanel` (`/provider list`). Rows reflow with terminal width.
  ResponsiveTable<ProviderDef> _buildProviderTable(
    List<ProviderDef> providers,
    GlueConfig config,
  ) {
    return ResponsiveTable<ProviderDef>(
      columns: const [
        TableColumn(key: 'name', header: 'PROVIDER', maxWidth: 24),
        TableColumn(key: 'id', header: 'ID', maxWidth: 14),
        TableColumn(key: 'status', header: 'STATUS', maxWidth: 12),
      ],
      rows: providers,
      includeHeaderInWidth: true,
      getValues: (p) => {
        'name': p.name,
        'id': p.id.styled.dim.toString(),
        'status': _statusLabel(p, config).styled.dim.toString(),
      },
    );
  }

  /// Open a filterable picker of all catalogued providers with their current
  /// connection status. Selection opens an action submenu (Connect /
  /// Disconnect / Test), mirroring the `_openHistoryActionPanel` pattern.
  Future<void> openProviderPanel({
    required GlueConfig config,
    required void Function(String message) addSystemMessage,
  }) async {
    final providers =
        config.catalogData.providers.values.where((p) => p.enabled).toList();
    if (providers.isEmpty) {
      addSystemMessage('No providers in the catalog.');
      _render();
      return;
    }

    final table = _buildProviderTable(providers, config);

    final options = <SelectOption<ProviderDef>>[];
    for (var i = 0; i < providers.length; i++) {
      final p = providers[i];
      options.add(
        SelectOption.responsive(
          value: p,
          build: (w) => table.renderRow(i, w),
          searchText: '${p.id} ${p.name} ${_statusLabel(p, config)}',
        ),
      );
    }

    final panel = SelectPanel<ProviderDef>(
      title: 'Providers',
      options: options,
      headerBuilder: table.renderHeader,
      searchHint: 'filter providers',
      barrier: BarrierStyle.dim,
      width: PanelFluid(0.8, 40),
      height: PanelFluid(0.7, 10),
    );
    _panelStack.add(panel);
    _render();

    unawaited(panel.selection.then((provider) {
      if (provider == null) {
        _panelStack.remove(panel);
        _render();
        return;
      }
      _openProviderActionPanel(
        config: config,
        parentPanel: panel,
        provider: provider,
        addSystemMessage: addSystemMessage,
      );
    }));
  }

  void _openProviderActionPanel({
    required GlueConfig config,
    required SelectPanel<ProviderDef> parentPanel,
    required ProviderDef provider,
    required void Function(String message) addSystemMessage,
  }) {
    final adapter = config.adapters.lookup(provider.adapter);
    final connected =
        adapter != null && adapter.isConnected(provider, config.credentials);
    final isLocal = provider.auth.kind == AuthKind.none;

    final actions = providerActionsFor(
      connected: connected,
      isLocal: isLocal,
    );
    final lines = actions.map((a) => a.label).toList();

    final actionPanel = PanelModal(
      title: provider.name,
      lines: lines,
      barrier: BarrierStyle.dim,
      height: PanelFixed(lines.length + 2),
      width: PanelFixed(32),
      selectable: true,
    );
    _panelStack.add(actionPanel);
    _render();

    actionPanel.selection.then((idx) async {
      _panelStack.remove(actionPanel);
      _panelStack.remove(parentPanel);
      if (idx == null) {
        _render();
        return;
      }
      final action = actions[idx];
      switch (action) {
        case ProviderAction.connect:
          await openProviderAdd(
            config: config,
            providerId: provider.id,
            addSystemMessage: addSystemMessage,
          );
        case ProviderAction.disconnect:
          config.credentials.remove(provider.id);
          final envVar = provider.auth.envVar;
          if (envVar != null && config.credentials.readEnv(envVar) != null) {
            addSystemMessage(
              'Forgot stored ${provider.name}. '
              '\$$envVar is still set and will keep being used.',
            );
          } else {
            addSystemMessage('Forgot stored ${provider.name}.');
          }
          _render();
        case ProviderAction.test:
          if (adapter == null) {
            addSystemMessage('No adapter for "${provider.adapter}".');
            _render();
            return;
          }
          if (isLocal) {
            addSystemMessage('${provider.name}: ok (no auth).');
            _render();
            return;
          }
          final resolved = config.resolveProviderById(provider.id);
          final health = adapter.validate(resolved);
          switch (health) {
            case ProviderHealth.ok:
              addSystemMessage('${provider.name}: ok.');
            case ProviderHealth.missingCredential:
              addSystemMessage(
                '${provider.name}: not connected. '
                'Run /provider add ${provider.id}.',
              );
            case ProviderHealth.unknownAdapter:
              addSystemMessage(
                '${provider.name}: adapter failed validation.',
              );
          }
          _render();
      }
    });
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

  Future<bool> _copyToClipboard(String text) =>
      shared_clipboard.copyToClipboard(text);
}
