import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue/src/commands/arg_completers.dart' as arg_completers;
import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/ui/api_key_prompt_panel.dart';
import 'package:glue/src/ui/device_code_panel.dart';
import 'package:glue/src/ui/panel_modal.dart';
import 'package:glue/src/ui/responsive_table.dart';
import 'package:glue/src/ui/select_panel.dart';
import 'package:glue/src/ui/table_formatter.dart';

enum _ProviderAction {
  connect('Connect'),
  disconnect('Disconnect'),
  test('Test');

  const _ProviderAction(this.label);
  final String label;
}

/// Local providers (auth: none) only support `Test`. Remote providers show
/// `Connect`/`Disconnect` (toggled on current state) plus `Test`.
List<_ProviderAction> _providerActionsFor({
  required bool connected,
  required bool isLocal,
}) {
  if (isLocal) return const [_ProviderAction.test];
  return [
    connected ? _ProviderAction.disconnect : _ProviderAction.connect,
    _ProviderAction.test,
  ];
}

/// `/provider` — manage configured providers (list, add, remove, test).
class ProviderCommand extends SlashCommand {
  ProviderCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'provider';

  @override
  String get description => 'Manage providers (list, add, remove, test)';

  @override
  SlashArgCompleter? get argCompleter => (prior, partial) {
        if (prior.isEmpty) {
          return arg_completers.providerSubcommandCandidates(partial);
        }
        if (prior.length == 1 &&
            const {'add', 'remove', 'test'}.contains(prior.first)) {
          final config = ctx.config;
          if (config == null) return const [];
          return arg_completers.providerIdCandidates(
            config.catalogData.providers,
            partial,
          );
        }
        return const [];
      };

  @override
  String execute(List<String> args) {
    final config = ctx.config;
    if (config == null) return 'Config not ready.';

    final subcommand = args.isEmpty ? 'list' : args.first.toLowerCase();
    final rest = args.length > 1 ? args.sublist(1) : const <String>[];

    switch (subcommand) {
      case 'list':
      case 'ls':
        _openListPanel(config);
        return '';
      case 'add':
        _openAddFlow(config, rest.isEmpty ? null : rest.first);
        return '';
      case 'remove':
      case 'rm':
        if (rest.isEmpty) return 'Usage: /provider remove <id>';
        return _remove(config, rest.first);
      case 'test':
        if (rest.isEmpty) return 'Usage: /provider test <id>';
        return _test(config, rest.first);
      default:
        return 'Usage: /provider [list|add|remove|test] [<id>]';
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // remove / test
  // ──────────────────────────────────────────────────────────────────────────

  String _remove(GlueConfig config, String id) {
    final p = config.catalogData.providers[id];
    if (p == null) return 'Unknown provider "$id".';
    config.credentials.remove(id);
    final envVar = p.auth.envVar;
    if (envVar != null && config.credentials.readEnv(envVar) != null) {
      return 'Forgot stored credentials for ${p.name}. '
          'Note: \$$envVar is still set and will keep being used.';
    }
    return 'Forgot stored credentials for ${p.name}.';
  }

  String _test(GlueConfig config, String id) {
    final p = config.catalogData.providers[id];
    if (p == null) return 'Unknown provider "$id".';
    final adapter = config.adapters.lookup(p.adapter);
    if (adapter == null) {
      return 'No adapter for wire protocol "${p.adapter}".';
    }
    final resolved = config.resolveProviderById(p.id);
    final health = adapter.validate(resolved);
    switch (health) {
      case ProviderHealth.ok:
        return '${p.name}: ok.';
      case ProviderHealth.missingCredential:
        return '${p.name}: missing credential. Run /provider add ${p.id}.';
      case ProviderHealth.unknownAdapter:
        return '${p.name}: adapter "${p.adapter}" failed validation.';
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // list / picker
  // ──────────────────────────────────────────────────────────────────────────

  void _openListPanel(GlueConfig config) {
    final providers =
        config.catalogData.providers.values.where((p) => p.enabled).toList();
    if (providers.isEmpty) {
      ctx.conversation.notify('No providers in the catalog.');
      return;
    }

    final table = _buildProviderTable(providers, config);
    final options = providers.indexed.map((e) {
      final (i, p) = e;
      return SelectOption.responsive(
        value: p,
        build: (w) => table.renderRow(i, w),
        searchText: '${p.id} ${p.name} ${_statusLabel(p, config)}',
      );
    }).toList();

    final panel = SelectPanel<ProviderDef>(
      title: 'Providers',
      options: options,
      headerBuilder: table.renderHeader,
      searchHint: 'filter providers',
      barrier: BarrierStyle.dim,
      width: PanelFluid(0.8, 40),
      height: PanelFluid(0.7, 10),
    );
    ctx.panels.push(panel);
    panel.selection.then((provider) {
      if (provider == null) {
        ctx.panels.dismiss(panel);
        return;
      }
      _openActionPanel(config, parentPanel: panel, provider: provider);
    });
  }

  void _openActionPanel(
    GlueConfig config, {
    required SelectPanel<ProviderDef> parentPanel,
    required ProviderDef provider,
  }) {
    final adapter = config.adapters.lookup(provider.adapter);
    final connected =
        adapter != null && adapter.isConnected(provider, config.credentials);
    final isLocal = provider.auth.kind == AuthKind.none;

    final actions = _providerActionsFor(connected: connected, isLocal: isLocal);
    final lines = actions.map((a) => a.label).toList();

    final actionPanel = PanelModal(
      title: provider.name,
      lines: lines,
      barrier: BarrierStyle.dim,
      height: PanelFixed(lines.length + 2),
      width: PanelFixed(32),
      selectable: true,
    );
    ctx.panels.push(actionPanel);

    actionPanel.selection.then((idx) async {
      ctx.panels.dismiss(actionPanel);
      ctx.panels.dismiss(parentPanel);
      if (idx == null) return;
      final action = actions[idx];
      switch (action) {
        case _ProviderAction.connect:
          await _runAddFlow(config, provider);
        case _ProviderAction.disconnect:
          config.credentials.remove(provider.id);
          final envVar = provider.auth.envVar;
          if (envVar != null && config.credentials.readEnv(envVar) != null) {
            ctx.conversation.notify(
              'Forgot stored ${provider.name}. '
              '\$$envVar is still set and will keep being used.',
            );
          } else {
            ctx.conversation.notify('Forgot stored ${provider.name}.');
          }
        case _ProviderAction.test:
          if (adapter == null) {
            ctx.conversation.notify('No adapter for "${provider.adapter}".');
            return;
          }
          if (isLocal) {
            ctx.conversation.notify('${provider.name}: ok (no auth).');
            return;
          }
          final resolved = config.resolveProviderById(provider.id);
          switch (adapter.validate(resolved)) {
            case ProviderHealth.ok:
              ctx.conversation.notify('${provider.name}: ok.');
            case ProviderHealth.missingCredential:
              ctx.conversation.notify(
                '${provider.name}: not connected. '
                'Run /provider add ${provider.id}.',
              );
            case ProviderHealth.unknownAdapter:
              ctx.conversation
                  .notify('${provider.name}: adapter failed validation.');
          }
      }
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // add / auth flows
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _openAddFlow(GlueConfig config, String? providerId) async {
    ProviderDef? provider;
    if (providerId != null) {
      provider = config.catalogData.providers[providerId];
      if (provider == null) {
        ctx.conversation.notify(
          'Unknown provider "$providerId". Try `/provider list`.',
        );
        return;
      }
    } else {
      provider = await _pickProviderForAdd(config);
      if (provider == null) return;
    }
    await _runAddFlow(config, provider);
  }

  Future<ProviderDef?> _pickProviderForAdd(GlueConfig config) async {
    final providers = config.catalogData.providers.values
        .where((p) => p.enabled && p.auth.kind != AuthKind.none)
        .toList();
    if (providers.isEmpty) return null;

    final table = _buildProviderTable(providers, config);
    final options = providers.indexed.map((e) {
      final (i, p) = e;
      return SelectOption.responsive(
        value: p,
        build: (w) => table.renderRow(i, w),
        searchText: '${p.id} ${p.name}',
      );
    }).toList();

    final panel = SelectPanel<ProviderDef>(
      title: 'Add provider',
      options: options,
      headerBuilder: table.renderHeader,
      searchHint: 'filter providers',
      width: PanelFluid(0.7, 40),
      height: PanelFluid(0.6, 10),
    );
    ctx.panels.push(panel);
    final picked = await panel.selection;
    ctx.panels.dismiss(panel);
    return picked;
  }

  Future<void> _runAddFlow(GlueConfig config, ProviderDef provider) async {
    if (provider.auth.kind == AuthKind.none) {
      ctx.conversation.notify('${provider.name} needs no credentials.');
      return;
    }

    final adapter = config.adapters.lookup(provider.adapter);
    if (adapter == null) {
      ctx.conversation
          .notify('No adapter for wire protocol "${provider.adapter}".');
      return;
    }

    final flow = await adapter.beginInteractiveAuth(
      provider: provider,
      store: config.credentials,
    );
    if (flow == null) {
      ctx.conversation.notify('${provider.name} needs no interactive setup.');
      return;
    }

    switch (flow) {
      case ApiKeyFlow():
        await _runApiKeyFlow(config, provider, flow);
      case DeviceCodeFlow():
        await _runDeviceCodeFlow(provider, flow);
      case PkceFlow():
        ctx.conversation.notify(
          'PKCE OAuth is not implemented yet for ${provider.name}.',
        );
    }
  }

  Future<void> _runApiKeyFlow(
    GlueConfig config,
    ProviderDef provider,
    ApiKeyFlow flow,
  ) async {
    final panel = ApiKeyPromptPanel(
      providerId: flow.providerId,
      providerName: flow.providerName,
      envVar: flow.envVar,
      envPresent: flow.envPresent,
      helpUrl: flow.helpUrl,
    );
    ctx.panels.push(panel);
    final value = await panel.result;
    ctx.panels.dismiss(panel);

    if (value == null) {
      ctx.conversation.notify('Cancelled.');
      return;
    }
    if (value.isEmpty && flow.envPresent != null) {
      ctx.conversation.notify(
        'Keeping env var \$${flow.envVar}. ${provider.name} connected.',
      );
      return;
    }

    config.credentials.setFields(provider.id, {'api_key': value});
    ctx.conversation.notify('Connected to ${provider.name}.');
  }

  Future<void> _runDeviceCodeFlow(
    ProviderDef provider,
    DeviceCodeFlow flow,
  ) async {
    final panel =
        DeviceCodePanel(flow: flow, onNeedsRender: ctx.conversation.render);
    ctx.panels.push(panel);
    final fields = await panel.result;
    ctx.panels.dismiss(panel);

    ctx.conversation.notify(
      fields == null
          ? '${provider.name} connection cancelled.'
          : 'Connected to ${provider.name}.',
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Shared table
  // ──────────────────────────────────────────────────────────────────────────

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

  String _statusLabel(ProviderDef p, GlueConfig config) {
    if (p.auth.kind == AuthKind.none) return 'no auth';
    final adapter = config.adapters.lookup(p.adapter);
    if (adapter != null && adapter.isConnected(p, config.credentials)) {
      return 'connected';
    }
    return 'missing';
  }
}
