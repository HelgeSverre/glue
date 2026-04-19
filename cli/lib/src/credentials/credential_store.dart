/// Resolves [CredentialRef]s to secret strings.
///
/// Reads and writes `~/.glue/credentials.json` with mode `0600` (owner-only).
/// Writes are atomic: the new contents are written to a sibling `.tmp` file,
/// permissions are set, and `rename(2)` replaces the original. Interrupted
/// writes can leave no orphaned tmp files in practice, but any found at
/// construction time can be ignored.
///
/// Credentials resolution intentionally does NOT log the resolved value.
/// Error messages include provider ids but never key fragments.
library;

import 'dart:convert';
import 'dart:io';

import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/credentials/credential_ref.dart';

class CredentialStore {
  CredentialStore({required this.path, Map<String, String>? env})
      : _env = env ?? Platform.environment;

  /// Absolute path to `credentials.json`.
  final String path;

  final Map<String, String> _env;

  /// Resolve a direct credential reference.
  String? resolve(CredentialRef ref) {
    return switch (ref) {
      NoCredential() => null,
      InlineCredential(:final value) => value,
      EnvCredential(:final name) => _env[name],
      StoredCredential(:final key) => _readStored()[key],
    };
  }

  /// Walk a provider's [AuthSpec] and return the `api_key` value when
  /// [AuthKind.apiKey]:
  ///   1. env var named in [AuthSpec.envVar] (if set + non-empty)
  ///   2. stored `api_key` field under the provider id
  ///
  /// Returns null for [AuthKind.none] and [AuthKind.oauth] — OAuth providers
  /// use [getField] to read their specific token fields.
  String? resolveForProvider(ProviderDef provider) {
    switch (provider.auth.kind) {
      case AuthKind.none:
      case AuthKind.oauth:
        return null;
      case AuthKind.apiKey:
        final envVar = provider.auth.envVar;
        if (envVar != null) {
          final v = _env[envVar];
          if (v != null && v.isNotEmpty) return v;
        }
        return _readStored()[provider.id];
    }
  }

  /// Convenience for the common single-field api-key providers.
  /// Equivalent to `setFields(providerId, {'api_key': value})`.
  void setApiKey(String providerId, String value) =>
      setFields(providerId, {'api_key': value});

  /// Multi-field write — replaces any existing fields under [providerId].
  /// OAuth providers use this to store `{github_token, copilot_token, ...}`
  /// in one atomic commit.
  void setFields(String providerId, Map<String, String> values) {
    final stored = _readRaw();
    final providers = (stored['providers'] as Map?) ?? <String, dynamic>{};
    providers[providerId] = <String, String>{...values};
    stored['version'] = 1;
    stored['providers'] = providers;
    _writeRaw(stored);
  }

  /// Read an environment variable from the captured env map.
  /// Adapters use this for the "[using $ENV]" pre-fill hint in auth flows.
  String? readEnv(String name) => _env[name];

  /// Read a single stored field for [providerId]. Returns null if the
  /// provider or field is absent.
  String? getField(String providerId, String fieldName) {
    final raw = _readRaw();
    final providers = raw['providers'];
    if (providers is! Map) return null;
    final provider = providers[providerId];
    if (provider is! Map) return null;
    final value = provider[fieldName];
    return value is String ? value : null;
  }

  /// Read all stored fields for [providerId]. Empty map if absent.
  Map<String, String> getFields(String providerId) {
    final raw = _readRaw();
    final providers = raw['providers'];
    if (providers is! Map) return const {};
    final provider = providers[providerId];
    if (provider is! Map) return const {};
    final out = <String, String>{};
    provider.forEach((key, value) {
      if (value is String) out[key.toString()] = value;
    });
    return out;
  }

  void remove(String providerId) {
    final stored = _readRaw();
    final providers = (stored['providers'] as Map?) ?? <String, dynamic>{};
    providers.remove(providerId);
    stored['version'] = 1;
    stored['providers'] = providers;
    _writeRaw(stored);
  }

  // --- internals ---

  Map<String, String> _readStored() {
    final raw = _readRaw();
    final providers = raw['providers'];
    if (providers is! Map) return const {};
    final out = <String, String>{};
    providers.forEach((key, value) {
      if (value is Map && value['api_key'] is String) {
        out[key.toString()] = value['api_key'] as String;
      }
    });
    return out;
  }

  /// Treats a corrupt or unreadable file as empty so `setApiKey` can always
  /// recover without the user manually deleting ~/.glue/credentials.json.
  Map<String, dynamic> _readRaw() {
    final file = File(path);
    if (!file.existsSync()) return <String, dynamic>{};
    final text = file.readAsStringSync().trim();
    if (text.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return <String, dynamic>{};
      return decoded.cast<String, dynamic>();
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  void _writeRaw(Map<String, dynamic> data) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final tmp = File('$path.tmp');
    tmp.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(data)}\n',
    );
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['600', tmp.path]);
    }
    tmp.renameSync(file.path);
  }
}
