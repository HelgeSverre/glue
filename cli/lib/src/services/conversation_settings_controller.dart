import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';

enum SettingsChangeOrigin { user, sessionRestore }

class SettingsChangeResult {
  const SettingsChangeResult({required this.applied, required this.message});

  final bool applied;
  final String message;
}

class PreparedConversationSettings {
  const PreparedConversationSettings({
    required this.config,
    required this.llm,
    this.warnings = const [],
  });

  final GlueConfig config;
  final LlmClient llm;
  final List<String> warnings;
}

class ConversationSessionResumeResult {
  const ConversationSessionResumeResult({
    required this.sessionResult,
    this.warnings = const [],
  });

  final SessionResumeResult sessionResult;
  final List<String> warnings;
}

typedef ConversationClientBuilder =
    LlmClient Function(GlueConfig config, String systemPrompt);

/// Coordinates the live model/reasoning selection and its two persistence
/// targets: the active session snapshot and the user's conversation defaults.
class ConversationSettingsController {
  ConversationSettingsController({
    required this.configGetter,
    required this.configSetter,
    required this.modelIdSetter,
    required this.agent,
    required this.session,
    required this.systemPrompt,
    required this.configWriter,
    this.ensureSession,
    ConversationClientBuilder? clientBuilder,
  }) : _clientBuilder =
           clientBuilder ??
           ((config, prompt) =>
               LlmClientFactory(config).createFromConfig(systemPrompt: prompt));

  final GlueConfig? Function() configGetter;
  final void Function(GlueConfig config) configSetter;
  final void Function(String modelId) modelIdSetter;
  final AgentCore agent;
  final SessionManager session;
  final String systemPrompt;
  final ConversationConfigWriter configWriter;
  final void Function()? ensureSession;
  final ConversationClientBuilder _clientBuilder;

  GlueConfig? get current => configGetter();

  SettingsChangeResult selectModel(
    ModelRef model, {
    required SettingsChangeOrigin origin,
    String? displayName,
  }) {
    final config = current;
    if (config == null) {
      return const SettingsChangeResult(
        applied: false,
        message: 'Config not ready.',
      );
    }

    try {
      final reasoning = _compatibleReasoning(config, model, config.reasoning);
      final next = config.copyWith(activeModel: model, reasoning: reasoning);
      final llm = _clientBuilder(next, systemPrompt);
      final applyWarning = _apply(next, llm, updateModel: true);

      var message = 'Switched to ${displayName ?? model}.';
      if (reasoning.effort != config.reasoning.effort) {
        message += ' Reasoning reset to Auto for this model.';
      }
      message += applyWarning;
      if (origin == SettingsChangeOrigin.user) {
        message += _persist(() {
          configWriter.setModelAndReasoning(model, reasoning);
        });
      }
      return SettingsChangeResult(applied: true, message: message);
    } on ConfigError catch (error) {
      return SettingsChangeResult(applied: false, message: error.message);
    } on Exception catch (error) {
      return SettingsChangeResult(applied: false, message: error.toString());
    }
  }

  SettingsChangeResult setReasoning(
    ReasoningConfig reasoning, {
    required SettingsChangeOrigin origin,
  }) {
    final config = current;
    if (config == null) {
      return const SettingsChangeResult(
        applied: false,
        message: 'Config not ready.',
      );
    }

    try {
      final compatible = _compatibleReasoning(
        config,
        config.activeModel,
        reasoning,
        normalize: false,
      );
      final next = config.copyWith(reasoning: compatible);
      final llm = _clientBuilder(next, systemPrompt);
      ensureSession?.call();
      final applyWarning = _apply(next, llm, updateModel: false);

      var message =
          'Reasoning: ${compatible.effort.name}; thoughts '
          '${compatible.showThoughts ? 'shown' : 'hidden'}.';
      message += applyWarning;
      if (origin == SettingsChangeOrigin.user) {
        message += _persist(() => configWriter.setReasoning(compatible));
      }
      return SettingsChangeResult(applied: true, message: message);
    } on ConfigError catch (error) {
      return SettingsChangeResult(applied: false, message: error.message);
    } on Exception catch (error) {
      return SettingsChangeResult(applied: false, message: error.toString());
    }
  }

  PreparedConversationSettings prepareRestore(SessionMeta meta) {
    final config = current;
    if (config == null) throw StateError('Config not ready.');

    final warnings = <String>[];
    var model = config.activeModel;
    final storedModel = ModelRef.tryParse(meta.modelRef);
    if (storedModel == null) {
      warnings.add(
        'Could not restore invalid session model "${meta.modelRef}"; '
        'keeping $model.',
      );
    } else {
      try {
        config.resolveModel(storedModel);
        model = storedModel;
      } on Exception {
        warnings.add(
          'Could not restore unavailable session model "$storedModel"; '
          'keeping $model.',
        );
      }
    }

    var effort = config.reasoning.effort;
    final storedEffort = meta.reasoningEffort;
    if (storedEffort != null) {
      final parsed = ReasoningEffort.values.where(
        (candidate) => candidate.name == storedEffort,
      );
      if (parsed.isEmpty) {
        warnings.add(
          'Could not restore invalid reasoning effort "$storedEffort"; '
          'keeping ${effort.name}.',
        );
      } else {
        effort = parsed.first;
      }
    }

    var reasoning = ReasoningConfig(
      effort: effort,
      showThoughts: meta.showThoughts ?? config.reasoning.showThoughts,
    );
    final compatible = _compatibleReasoning(config, model, reasoning);
    if (compatible.effort != reasoning.effort) {
      warnings.add(
        'Reasoning effort "${reasoning.effort.name}" is not supported by '
        '"$model"; using auto.',
      );
      reasoning = compatible;
    }

    var next = config.copyWith(activeModel: model, reasoning: reasoning);
    try {
      return PreparedConversationSettings(
        config: next,
        llm: _clientBuilder(next, systemPrompt),
        warnings: warnings,
      );
    } on Exception {
      if (model == config.activeModel) rethrow;
      warnings.add(
        'Could not create a client for session model "$model"; '
        'keeping ${config.activeModel}.',
      );
      model = config.activeModel;
      reasoning = _compatibleReasoning(config, model, reasoning);
      next = config.copyWith(activeModel: model, reasoning: reasoning);
      return PreparedConversationSettings(
        config: next,
        llm: _clientBuilder(next, systemPrompt),
        warnings: warnings,
      );
    }
  }

  ConversationSessionResumeResult resume(SessionMeta meta) {
    PreparedConversationSettings? prepared;
    final warnings = <String>[];
    try {
      prepared = prepareRestore(meta);
      warnings.addAll(prepared.warnings);
    } on Exception catch (error) {
      warnings.add(
        'Could not prepare the session settings; keeping the current '
        'selection ($error).',
      );
    }
    final result = session.resumeSession(session: meta, agent: agent);
    if (result.status != SessionResumeStatus.locked && prepared != null) {
      final warning = applyRestore(prepared);
      if (warning.isNotEmpty) warnings.add(warning.trim());
    }
    return ConversationSessionResumeResult(
      sessionResult: result,
      warnings: warnings,
    );
  }

  String applyRestore(PreparedConversationSettings prepared) =>
      _apply(prepared.config, prepared.llm, updateModel: true);

  ReasoningConfig _compatibleReasoning(
    GlueConfig config,
    ModelRef model,
    ReasoningConfig reasoning, {
    bool normalize = true,
  }) {
    final support = config.resolveModel(model).def.reasoning;
    if (reasoning.effort == ReasoningEffort.auto ||
        (support != null && support.supports(reasoning.effort))) {
      return reasoning;
    }
    if (!normalize) {
      final allowed = support?.efforts.map((value) => value.name).join(', ');
      throw ConfigError(
        'Reasoning effort "${reasoning.effort.name}" is not supported by '
        '"$model". Supported: '
        '${allowed?.isNotEmpty == true ? allowed : 'auto'}.',
      );
    }
    return reasoning.copyWith(effort: ReasoningEffort.auto);
  }

  String _apply(GlueConfig config, LlmClient llm, {required bool updateModel}) {
    agent.llm = llm;
    agent.modelId = config.activeModel.modelId;
    configSetter(config);
    modelIdSetter(config.activeModel.modelId);
    try {
      if (updateModel) {
        session.updateSessionModel(modelRef: config.activeModel.toString());
      }
      session.updateSessionReasoning(
        effort: config.reasoning.effort,
        showThoughts: config.reasoning.showThoughts,
      );
      return '';
    } on Exception catch (error) {
      return ' Warning: the runtime changed, but the session snapshot could '
          'not be updated ($error).';
    }
  }

  String _persist(void Function() write) {
    try {
      write();
      return '';
    } on Exception catch (error) {
      return ' Warning: could not update config.yaml; this change is '
          'session-only ($error).';
    }
  }
}
