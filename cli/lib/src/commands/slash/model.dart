import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue/src/commands/arg_completers.dart' as arg_completers;
import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/ui/model_panel_formatter.dart';
import 'package:glue/src/ui/panel_modal.dart';
import 'package:glue/src/ui/select_panel.dart';

/// `/model` — pick a model from a filtered catalog, or switch directly by ref.
class ModelCommand extends SlashCommand {
  ModelCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'model';

  @override
  String get description =>
      'Switch model (no args = picker, with arg = switch directly)';

  @override
  SlashArgCompleter? get argCompleter => (prior, partial) {
        if (prior.isNotEmpty) return const [];
        final config = ctx.config;
        if (config == null) return const [];
        return arg_completers.modelRefCandidates(
          config.catalogData.providers,
          partial,
        );
      };

  @override
  String execute(List<String> args) {
    if (args.isEmpty) {
      _openPicker();
      return '';
    }
    return _switchByQuery(args.join(' '));
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Picker
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _openPicker() async {
    final config = ctx.config;
    if (config == null) {
      ctx.conversation.notify('Config not ready.');
      return;
    }

    // Show models that are tool-capable AND whose provider has credentials.
    const defaultCaps = <String>{Capability.chat, Capability.tools};
    var entries = flattenCatalog(
      config.catalogData,
      where: (p) {
        final adapter = config.adapters.lookup(p.adapter);
        return adapter != null && adapter.isConnected(p, config.credentials);
      },
    ).where((row) => row.model.capabilities.containsAll(defaultCaps)).toList();

    // Optionally enrich with installed-models discovery from a local Ollama.
    final ollamaProvider = config.catalogData.providers['ollama'];
    if (ollamaProvider != null && ollamaProvider.enabled) {
      final discovery = OllamaDiscovery(
        baseUrl: Uri.parse(
          ollamaProvider.baseUrl ?? 'http://localhost:11434',
        ),
      );
      final installed = await discovery.listInstalled();
      entries = mergeOllamaDiscovery(entries, installed);
    }

    if (entries.isEmpty) {
      ctx.conversation.notify(
        'No models available. Run `/provider add <id>` to connect one.',
      );
      return;
    }

    final builder = buildModelPanel(entries, currentRef: config.activeModel);
    final options = entries.indexed.map((e) {
      final (i, entry) = e;
      final searchText = stripAnsi(
        '${entry.providerName} ${entry.model.name} '
        '${entry.model.notes ?? ''}',
      );
      return SelectOption.responsive(
        value: entry,
        build: (w) => builder.renderRow(i, w),
        searchText: searchText,
      );
    }).toList();

    final panel = SelectPanel<CatalogRow>(
      title: 'Switch Model',
      options: options,
      headerBuilder: builder.renderHeader,
      searchHint: 'filter models',
      barrier: BarrierStyle.dim,
      width: PanelFluid(0.8, 30),
      height: PanelFluid(0.7, 10),
      initialIndex: builder.initialIndex,
    );
    ctx.panels.push(panel);
    panel.selection.then((entry) {
      ctx.panels.dismiss(panel);
      if (entry == null) return;
      final result = ctx.switchModel(entry);
      if (result.isNotEmpty) ctx.conversation.notify(result);
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Switch by query
  // ──────────────────────────────────────────────────────────────────────────

  String _switchByQuery(String query) {
    final config = ctx.config;
    if (config == null) return 'Config not ready.';

    final outcome = resolveModelInput(query, config.catalogData);
    switch (outcome) {
      case ResolvedExact():
        final provider = config.catalogData.providers[outcome.ref.providerId]!;
        return ctx.switchModel((
          providerId: provider.id,
          providerName: provider.name,
          model: outcome.def,
          availability: ModelAvailability.unknown,
        ));
      case ResolvedPassthrough():
        if (!outcome.providerKnown) {
          return 'Unknown provider "${outcome.ref.providerId}". '
              'Run `/model` to pick a model.';
        }
        final provider = config.catalogData.providers[outcome.ref.providerId]!;
        final synthetic = ModelDef(
          id: outcome.ref.modelId,
          name: outcome.ref.modelId,
        );
        return ctx.switchModel((
          providerId: provider.id,
          providerName: provider.name,
          model: synthetic,
          availability: ModelAvailability.unknown,
        ));
      case AmbiguousBareInput():
        final options = outcome.candidates.map((c) => '  ${c.ref}').join('\n');
        return 'Model "$query" is ambiguous. Pick one:\n$options';
      case UnknownBareInput():
        final hint = config.catalogData.providers.values
            .expand((p) => p.models.values.map((m) => '${p.id}/${m.id}'))
            .take(12)
            .join(', ');
        return 'Unknown model: $query\n'
            'Use `<provider>/<id>` (e.g. `ollama/gemma4:latest`) or one of: '
            '$hint …';
    }
  }
}
