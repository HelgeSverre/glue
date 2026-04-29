/// Builds a minimal valid [GlueConfig] for tests without touching disk or env.
library;

import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:glue_strategies/glue_strategies.dart';

GlueConfig testConfig({
  ModelRef? activeModel,
  ModelCatalog? catalog,
  Map<String, String> env = const {},
  String credentialsPath = '/tmp/glue_test_credentials.json',
}) {
  final effectiveCatalog = catalog ?? bundledCatalog;
  return GlueConfig(
    activeModel: activeModel ?? ModelRef.parse(effectiveCatalog.defaults.model),
    catalogData: effectiveCatalog,
    credentials: CredentialStore(path: credentialsPath, env: env),
    adapters: AdapterRegistry([
      AnthropicAdapter(),
      OpenAiCompatibleAdapter(),
      OllamaAdapter(),
    ]),
  );
}
