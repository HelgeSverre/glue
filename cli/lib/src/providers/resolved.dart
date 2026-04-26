/// Glue-native value types that bundle a [ProviderDef] / [ModelDef] with
/// runtime-resolved data (credential, compatibility profile).
///
/// Adapters consume these and never read the environment or credential store
/// directly, so the credential boundary stays single-hop.
library;

import 'package:glue/src/catalog/model_catalog.dart';

class ResolvedProvider {
  const ResolvedProvider({
    required this.def,
    this.apiKey,
    this.credentials = const {},
  });

  final ProviderDef def;

  /// The resolved api-key value (env > stored) for [AuthKind.apiKey]
  /// providers. Null for oauth/none kinds.
  final String? apiKey;

  /// All stored credential fields for this provider. Used by OAuth adapters
  /// (`github_token`, `copilot_token`, `copilot_token_expires_at`) and by
  /// multi-field API-key providers in the future. For plain api-key
  /// providers this is `{api_key: <value>}` when stored, empty otherwise.
  final Map<String, String> credentials;

  String get id => def.id;
  String get adapter => def.adapter;
  String? get baseUrl => def.baseUrl;
  Map<String, String> get requestHeaders => def.requestHeaders;

  /// When the catalog omits `compatibility`, default to the adapter id.
  /// This keeps vanilla OpenAI the default; provider quirks opt in by name.
  String get compatibility => def.compatibility ?? def.adapter;

  /// Return a copy with [apiKey] replaced — and the matching
  /// `credentials['api_key']` field updated to keep the two views in sync
  /// (see field doc above). Used by the API-key-prompt flow to probe a
  /// just-entered key without persisting it to the credential store first.
  ResolvedProvider withApiKey(String? apiKey) {
    final mergedCredentials = Map<String, String>.from(credentials);
    if (apiKey == null || apiKey.isEmpty) {
      mergedCredentials.remove('api_key');
    } else {
      mergedCredentials['api_key'] = apiKey;
    }
    return ResolvedProvider(
      def: def,
      apiKey: apiKey,
      credentials: mergedCredentials,
    );
  }
}

class ResolvedModel {
  const ResolvedModel({required this.def, required this.provider});

  final ModelDef def;
  final ProviderDef provider;

  String get id => def.id;
  String get name => def.name;
  String get apiId => def.apiId;
}
