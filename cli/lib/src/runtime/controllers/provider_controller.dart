import 'dart:async';
import 'package:glue/src/runtime/transcript.dart';

import 'package:meta/meta.dart';

import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/runtime/services/config.dart';
import 'package:glue/src/providers/api_key_prompt_panel.dart';
import 'package:glue/src/providers/auth_flow.dart';
import 'package:glue/src/providers/device_code_panel.dart';
import 'package:glue/src/providers/provider_adapter.dart';
import 'package:glue/src/runtime/commands/command_host.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/ui/components/panel.dart';
import 'package:glue/src/ui/components/tables.dart';
import 'package:glue/src/ui/services/panels.dart';

/// Actions offered on a selected provider in `/provider`'s action submenu.
/// Public so the list-builder ([providerActionsFor]) can be unit-tested.
enum ProviderAction {
  connect('Connect'),
  disconnect('Disconnect'),
  test('Test');

  const ProviderAction(this.label);
  final String label;
}

/// Decide which actions the provider action panel should offer for a given
/// provider state.
///
/// - Local providers (auth: none) can only be tested — there's nothing to
///   connect to or disconnect from.
/// - Remote providers show Connect-or-Disconnect depending on state, plus Test.
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

class ProviderController implements ProviderCommandController {
  const ProviderController({
    required this.config,
    required this.panels,
    required this.transcript,
    required this.render,
  });

  final Config config;
  final Panels panels;
  final Transcript transcript;
  final void Function() render;

  @override
  String runProviderCommand(List<String> args) {
    final cfg = config.current;
    if (cfg == null) return 'Config not ready.';

    final subcommand = args.isEmpty ? 'list' : args.first.toLowerCase();
    final rest = args.length > 1 ? args.sublist(1) : const <String>[];

    switch (subcommand) {
      case 'list':
      case 'ls':
        unawaited(openProviderPanel(cfg));
        return '';
      case 'add':
        unawaited(openProviderAdd(
          config: cfg,
          providerId: rest.isEmpty ? null : rest.first,
        ));
        return '';
      case 'remove':
      case 'rm':
        if (rest.isEmpty) return 'Usage: /provider remove <id>';
        return _providerRemove(cfg, rest.first);
      case 'test':
        if (rest.isEmpty) return 'Usage: /provider test <id>';
        return _providerTest(cfg, rest.first);
      default:
        return 'Usage: /provider [list|add|remove|test] [<id>]';
    }
  }

  @visibleForTesting
  Future<void> openProviderPanel(GlueConfig config) async {
    final providers =
        config.catalogData.providers.values.where((p) => p.enabled).toList();
    if (providers.isEmpty) {
      transcript.system('No providers in the catalog.');
      render();
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
    panels.push(panel);

    unawaited(panel.selection.then((provider) {
      if (provider == null) {
        panels.remove(panel);
        return;
      }
      _openProviderActionPanel(
        config: config,
        parentPanel: panel,
        provider: provider,
      );
    }));
  }

  Future<void> openProviderAdd({
    required GlueConfig config,
    required String? providerId,
  }) async {
    ProviderDef? provider;
    if (providerId != null) {
      provider = config.catalogData.providers[providerId];
      if (provider == null) {
        transcript.system(
          'Unknown provider "$providerId". Try `/provider list`.',
        );
        render();
        return;
      }
    } else {
      provider = await _pickProvider(config);
      if (provider == null) {
        render();
        return;
      }
    }

    if (provider.auth.kind == AuthKind.none) {
      transcript.system('${provider.name} needs no credentials.');
      render();
      return;
    }

    final adapter = config.adapters.lookup(provider.adapter);
    if (adapter == null) {
      transcript.system(
        'No adapter for wire protocol "${provider.adapter}".',
      );
      render();
      return;
    }

    final flow = await adapter.beginInteractiveAuth(
      provider: provider,
      store: config.credentials,
    );
    if (flow == null) {
      transcript.system('${provider.name} needs no interactive setup.');
      render();
      return;
    }

    switch (flow) {
      case ApiKeyFlow():
        await _runApiKeyFlow(
          config: config,
          provider: provider,
          flow: flow,
        );
      case DeviceCodeFlow():
        await _runDeviceCodeFlow(
          provider: provider,
          flow: flow,
        );
      case PkceFlow():
        transcript.system(
          'PKCE OAuth is not implemented yet for ${provider.name}.',
        );
        render();
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
    panels.push(panel);
    final picked = await panel.selection;
    panels.remove(panel);
    return picked;
  }

  Future<void> _runApiKeyFlow({
    required GlueConfig config,
    required ProviderDef provider,
    required ApiKeyFlow flow,
  }) async {
    final panel = ApiKeyPromptPanel(
      providerId: flow.providerId,
      providerName: flow.providerName,
      envVar: flow.envVar,
      envPresent: flow.envPresent,
      helpUrl: flow.helpUrl,
    );
    panels.push(panel);
    final value = await panel.result;
    panels.remove(panel);

    if (value == null) {
      transcript.system('Cancelled.');
      render();
      return;
    }
    if (value.isEmpty && flow.envPresent != null) {
      transcript.system(
        'Keeping env var \$${flow.envVar}. ${provider.name} connected.',
      );
      render();
      return;
    }

    config.credentials.setFields(provider.id, {'api_key': value});
    transcript.system('Connected to ${provider.name}.');
    render();
  }

  Future<void> _runDeviceCodeFlow({
    required ProviderDef provider,
    required DeviceCodeFlow flow,
  }) async {
    final panel = DeviceCodePanel(flow: flow, onNeedsRender: render);
    panels.push(panel);
    final fields = await panel.result;
    panels.remove(panel);

    if (fields == null) {
      transcript.system('${provider.name} connection cancelled.');
    } else {
      transcript.system('Connected to ${provider.name}.');
    }
    render();
  }

  String _statusLabel(ProviderDef p, GlueConfig config) {
    if (p.auth.kind == AuthKind.none) return 'no auth';
    final adapter = config.adapters.lookup(p.adapter);
    if (adapter != null && adapter.isConnected(p, config.credentials)) {
      return 'connected';
    }
    return 'missing';
  }

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

  void _openProviderActionPanel({
    required GlueConfig config,
    required SelectPanel<ProviderDef> parentPanel,
    required ProviderDef provider,
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

    final actionPanel = Panel(
      title: provider.name,
      lines: lines,
      barrier: BarrierStyle.dim,
      height: PanelFixed(lines.length + 2),
      width: PanelFixed(32),
      selectable: true,
    );
    panels.push(actionPanel);

    actionPanel.selection.then((idx) async {
      panels.remove(actionPanel);
      panels.remove(parentPanel);
      if (idx == null) {
        render();
        return;
      }
      final action = actions[idx];
      switch (action) {
        case ProviderAction.connect:
          await openProviderAdd(
            config: config,
            providerId: provider.id,
          );
        case ProviderAction.disconnect:
          config.credentials.remove(provider.id);
          final envVar = provider.auth.envVar;
          if (envVar != null && config.credentials.readEnv(envVar) != null) {
            transcript.system(
              'Forgot stored ${provider.name}. '
              '\$$envVar is still set and will keep being used.',
            );
          } else {
            transcript.system('Forgot stored ${provider.name}.');
          }
          render();
        case ProviderAction.test:
          if (adapter == null) {
            transcript.system('No adapter for "${provider.adapter}".');
            render();
            return;
          }
          if (isLocal) {
            transcript.system('${provider.name}: ok (no auth).');
            render();
            return;
          }
          final resolved = config.resolveProviderById(provider.id);
          final health = adapter.validate(resolved);
          switch (health) {
            case ProviderHealth.ok:
              transcript.system('${provider.name}: ok.');
            case ProviderHealth.missingCredential:
              transcript.system(
                '${provider.name}: not connected. '
                'Run /provider add ${provider.id}.',
              );
            case ProviderHealth.unknownAdapter:
              transcript.system(
                '${provider.name}: adapter failed validation.',
              );
          }
          render();
      }
    });
  }

  String _providerRemove(GlueConfig config, String id) {
    final provider = config.catalogData.providers[id];
    if (provider == null) return 'Unknown provider "$id".';
    config.credentials.remove(id);
    final envVar = provider.auth.envVar;
    if (envVar != null && config.credentials.readEnv(envVar) != null) {
      return 'Forgot stored credentials for ${provider.name}. '
          'Note: \$$envVar is still set and will keep being used.';
    }
    return 'Forgot stored credentials for ${provider.name}.';
  }

  String _providerTest(GlueConfig config, String id) {
    final provider = config.catalogData.providers[id];
    if (provider == null) return 'Unknown provider "$id".';
    final adapter = config.adapters.lookup(provider.adapter);
    if (adapter == null) {
      return 'No adapter for wire protocol "${provider.adapter}".';
    }
    final resolved = config.resolveProviderById(provider.id);
    final health = adapter.validate(resolved);
    switch (health) {
      case ProviderHealth.ok:
        return '${provider.name}: ok.';
      case ProviderHealth.missingCredential:
        return '${provider.name}: missing credential. Run /provider add ${provider.id}.';
      case ProviderHealth.unknownAdapter:
        return '${provider.name}: adapter "${provider.adapter}" failed validation.';
    }
  }

}
