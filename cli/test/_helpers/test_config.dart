/// Builds a minimal valid [GlueConfig] for tests without touching disk or env.
library;

import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/catalog/models_generated.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/credentials/credential_store.dart';
import 'package:glue/src/providers/anthropic_adapter.dart';
import 'package:glue/src/providers/openai_compatible_adapter.dart';
import 'package:glue/src/providers/provider_adapter.dart';

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
    ]),
  );
}
