import 'dart:async';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/catalog/model_panel_formatter.dart';
import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/catalog/model_resolver.dart';
import 'package:glue/src/commands/arg_completers.dart' as arg_completers;
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/providers/llm_client_factory.dart';
import 'package:glue/src/providers/ollama_discovery.dart';
import 'package:glue/src/runtime/commands/command_host.dart';
import 'package:glue/src/runtime/controllers/confirmation_host.dart';
import 'package:glue/src/runtime/services/config.dart';
import 'package:glue/src/runtime/services/session.dart';
import 'package:glue/src/ui/components/modal.dart';
import 'package:glue/src/ui/components/panel.dart';
import 'package:glue/src/ui/rendering/ansi_utils.dart';
import 'package:glue/src/ui/services/panels.dart';

class ModelController implements ModelCommandController {
  const ModelController({
    required this.config,
    required this.getLlmFactory,
    required this.getSystemPrompt,
    required this.agent,
    required this.session,
    required this.panels,
    required this.confirmationHost,
    required this.addSystemMessage,
    required this.render,
    required this.setModelId,
  });

  final Config config;
  final LlmClientFactory? Function() getLlmFactory;
  final String? Function() getSystemPrompt;
  final Agent agent;
  final Session session;
  final Panels panels;
  final ConfirmationHost confirmationHost;
  final void Function(String message) addSystemMessage;
  final void Function() render;
  final void Function(String modelId) setModelId;

  @override
  void openModelPanel() {
    final cfg = config.current;
    if (cfg == null) return;

    final ollamaProvider = cfg.catalogData.providers['ollama'];
    final discovery = (ollamaProvider != null && ollamaProvider.enabled)
        ? OllamaDiscovery(
            baseUrl: Uri.parse(
              ollamaProvider.baseUrl ?? 'http://localhost:11434',
            ),
          )
        : null;

    unawaited(_openModelPanel(
      cfg: cfg,
      currentRef: cfg.activeModel,
      ollamaDiscovery: discovery,
    ));
  }

  Future<void> _openModelPanel({
    required GlueConfig cfg,
    required ModelRef currentRef,
    OllamaDiscovery? ollamaDiscovery,
  }) async {
    final defaultCaps = <String>{Capability.chat, Capability.tools};
    var entries = flattenCatalog(
      cfg.catalogData,
      where: (p) {
        final adapter = cfg.adapters.lookup(p.adapter);
        return adapter != null && adapter.isConnected(p, cfg.credentials);
      },
    ).where((row) => row.model.capabilities.containsAll(defaultCaps)).toList();

    if (ollamaDiscovery != null) {
      final installed = await ollamaDiscovery.listInstalled();
      entries = mergeOllamaDiscovery(entries, installed);
    }

    if (entries.isEmpty) {
      addSystemMessage(
        'No models available. Run `/provider add <id>` to connect one.',
      );
      render();
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
    panels.push(panel);

    unawaited(panel.selection.then((entry) {
      panels.remove(panel);
      if (entry == null) return;
      final result = switchToRow(entry);
      if (result.isNotEmpty) addSystemMessage(result);
      render();
    }));
  }

  @override
  String switchModelByQuery(String query) {
    final cfg = config.current;
    if (cfg == null) return 'Config not ready.';

    final outcome = resolveModelInput(query, cfg.catalogData);
    switch (outcome) {
      case ResolvedExact():
        final provider = cfg.catalogData.providers[outcome.ref.providerId]!;
        return switchToRow((
          providerId: provider.id,
          providerName: provider.name,
          model: outcome.def,
          availability: ModelAvailability.unknown,
        ));
      case ResolvedPassthrough():
        if (!outcome.providerKnown) {
          return 'Unknown provider "${outcome.ref.providerId}". '
              'Run `/models` to list available providers.';
        }
        final provider = cfg.catalogData.providers[outcome.ref.providerId]!;
        final synthetic = ModelDef(
          id: outcome.ref.modelId,
          name: outcome.ref.modelId,
        );
        return switchToRow((
          providerId: provider.id,
          providerName: provider.name,
          model: synthetic,
          availability: ModelAvailability.unknown,
        ));
      case AmbiguousBareInput():
        final options = outcome.candidates.map((c) => '  ${c.ref}').join('\n');
        return 'Model "$query" is ambiguous. Pick one:\n$options';
      case UnknownBareInput():
        final hint = cfg.catalogData.providers.values
            .expand((p) => p.models.values.map((m) => '${p.id}/${m.id}'))
            .take(12)
            .join(', ');
        return 'Unknown model: $query\n'
            'Use `<provider>/<id>` (e.g. `ollama/gemma4:latest`) or one of: '
            '$hint …';
    }
  }

  @override
  List<SlashArgCandidate> modelArgCandidates(
    List<String> prior,
    String partial,
  ) {
    if (prior.isNotEmpty) return const [];
    final cfg = config.current;
    if (cfg == null) return const [];
    return arg_completers.modelRefCandidates(
      cfg.catalogData.providers,
      partial,
    );
  }

  String switchToRow(CatalogRow row) {
    if (row.providerId == 'ollama' &&
        row.availability != ModelAvailability.installed &&
        row.availability != ModelAvailability.installedOnly) {
      final cfg = config.current;
      if (cfg != null) {
        final provider = cfg.catalogData.providers['ollama'];
        if (provider != null) {
          final discovery = OllamaDiscovery(
            baseUrl: Uri.parse(provider.baseUrl ?? 'http://localhost:11434'),
          );
          unawaited(_confirmAndPullOllamaModel(
            tag: row.model.id,
            discovery: discovery,
            onPull: () {
              final message = _applyModelSwitch(row);
              addSystemMessage(message);
              render();
            },
          ));
          return '';
        }
      }
    }

    return _applyModelSwitch(row);
  }

  Future<void> _confirmAndPullOllamaModel({
    required String tag,
    required OllamaDiscovery discovery,
    required void Function() onPull,
  }) async {
    final installed = await discovery.listInstalled();
    final isPresent = installed.any((m) => m.tag == tag);
    if (installed.isEmpty || isPresent) {
      onPull();
      return;
    }

    final approved = await confirmationHost.confirm(
      title: "Pull '$tag' from Ollama?",
      bodyLines: const [
        'Model is not installed locally.',
        'This downloads several GB and may take a while.',
      ],
      choices: const [
        ModalChoice('Yes', 'y'),
        ModalChoice('No', 'n'),
      ],
    );

    if (!approved) {
      addSystemMessage('Pull aborted — model not switched.');
      render();
      return;
    }

    addSystemMessage("Pulling '$tag' from Ollama…");
    render();

    discovery.invalidateCache();

    String? lastStatus;
    OllamaPullProgress? finalFrame;
    try {
      await for (final frame in discovery.pullModel(tag)) {
        finalFrame = frame;
        if (frame.hasError) break;
        if (frame.status != lastStatus) {
          lastStatus = frame.status;
          addSystemMessage('  ${frame.status}');
          render();
        }
      }
    } catch (e) {
      addSystemMessage('Pull failed: $e');
      render();
      return;
    }

    if (finalFrame == null || finalFrame.hasError) {
      final err = finalFrame?.error ?? 'unknown error';
      addSystemMessage('Pull failed: $err');
      render();
      return;
    }

    if (!finalFrame.isSuccess) {
      addSystemMessage(
        'Pull ended without success (last status: ${finalFrame.status}).',
      );
      render();
      return;
    }

    discovery.invalidateCache();
    onPull();
  }

  String _applyModelSwitch(CatalogRow row) {
    final factory = getLlmFactory();
    final cfg = config.current;
    final prompt = getSystemPrompt();
    final ref = ModelRef(providerId: row.providerId, modelId: row.model.id);
    if (factory != null && cfg != null && prompt != null) {
      final llm = factory.createFor(ref, systemPrompt: prompt);
      agent.llm = llm;
      config.update(cfg.copyWith(activeModel: ref));
    }
    setModelId(ref.modelId);
    session.updateModel(ref.toString());
    return 'Switched to ${row.model.name}';
  }
}
