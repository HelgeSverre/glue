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

enum CredentialHealth { ok, missing }

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

  /// Walk a provider's [AuthSpec] and try each source in turn.
  ///
  /// Resolution order for [AuthKind.env]:
  ///   1. env var named in [AuthSpec.envVar]
  ///   2. stored key under the same provider id (same id as [ProviderDef.id])
  ///
  /// [AuthKind.none] always returns null (valid for e.g. Ollama).
  /// [AuthKind.prompt] reads from the stored file only.
  String? resolveForProvider(ProviderDef provider) {
    switch (provider.auth.kind) {
      case AuthKind.none:
        return null;
      case AuthKind.env:
        final envVar = provider.auth.envVar;
        if (envVar != null) {
          final v = _env[envVar];
          if (v != null && v.isNotEmpty) return v;
        }
        return _readStored()[provider.id];
      case AuthKind.prompt:
        return _readStored()[provider.id];
    }
  }

  /// Is this provider's credential available?
  CredentialHealth health(ProviderDef provider) {
    if (provider.auth.kind == AuthKind.none) return CredentialHealth.ok;
    final resolved = resolveForProvider(provider);
    return (resolved != null && resolved.isNotEmpty)
        ? CredentialHealth.ok
        : CredentialHealth.missing;
  }

  void setApiKey(String providerId, String value) {
    final stored = _readRaw();
    final providers = (stored['providers'] as Map?) ?? <String, dynamic>{};
    providers[providerId] = {'api_key': value};
    stored['version'] = 1;
    stored['providers'] = providers;
    _writeRaw(stored);
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
