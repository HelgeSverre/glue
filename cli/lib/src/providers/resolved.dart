/// Glue-native value types that bundle a [ProviderDef] / [ModelDef] with
/// runtime-resolved data (credential, compatibility profile).
///
/// Adapters consume these and never read the environment or credential store
/// directly, so the credential boundary stays single-hop.
library;

import 'package:glue/src/catalog/model_catalog.dart';

class ResolvedProvider {
  const ResolvedProvider({required this.def, required this.apiKey});

  final ProviderDef def;

  /// The resolved credential, or null when none is configured
  /// (Ollama with `api_key: none`) or required but missing.
  final String? apiKey;

  String get id => def.id;
  String get adapter => def.adapter;
  String? get baseUrl => def.baseUrl;
  Map<String, String> get requestHeaders => def.requestHeaders;

  /// When the catalog omits `compatibility`, default to the adapter id.
  /// This keeps vanilla OpenAI the default; provider quirks opt in by name.
  String get compatibility => def.compatibility ?? def.adapter;
}

class ResolvedModel {
  const ResolvedModel({required this.def, required this.provider});

  final ModelDef def;
  final ProviderDef provider;

  String get id => def.id;
  String get name => def.name;
}
