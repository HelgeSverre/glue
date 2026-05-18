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

/// A pass-through workspace for tests that need to construct file tools.
///
/// Uses an identity [WorkspaceMapping] so paths handed in by the test
/// flow straight to `dart:io` without translation — exactly what tests
/// using `Directory.systemTemp` fixtures want.
Workspace testWorkspace([String cwd = '/']) =>
    LocalWorkspace(WorkspaceMapping.host(cwd));
