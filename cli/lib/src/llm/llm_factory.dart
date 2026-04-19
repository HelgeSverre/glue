import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/config/glue_config.dart';

/// Creates [LlmClient] instances from a [ModelRef] via the adapter registry.
///
/// The legacy provider-enum switch is gone — every client flows through
/// `catalog → resolved provider + model → adapter.createClient`.
class LlmClientFactory {
  LlmClientFactory(this._config);

  final GlueConfig _config;

  /// Build an [LlmClient] for [ref]. Resolves the provider (credentials
  /// included), looks up the adapter by wire protocol, and delegates.
  ///
  /// Throws [ConfigError] when the provider is unknown or the adapter has
  /// not been registered.
  LlmClient createFor(ModelRef ref, {required String systemPrompt}) {
    final provider = _config.resolveProvider(ref);
    final model = _config.resolveModel(ref);
    final adapter = _config.adapters.lookup(provider.adapter);
    if (adapter == null) {
      throw ConfigError(
        'no adapter registered for wire protocol "${provider.adapter}" '
        '(provider "${provider.id}").',
      );
    }
    return adapter.createClient(
      provider: provider,
      model: model,
      systemPrompt: systemPrompt,
    );
  }

  /// Shortcut: use the config's [GlueConfig.activeModel].
  LlmClient createFromConfig({required String systemPrompt}) =>
      createFor(_config.activeModel, systemPrompt: systemPrompt);
}
