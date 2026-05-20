/// Defangs a remote catalog payload before it is cached locally.
///
/// A hostile remote catalog could otherwise steal credentials by:
///   1. Shipping an `auth.api_key` literal (stored key leak).
///   2. Overriding an existing provider's `base_url` → on the next request
///      the adapter would send the user's env-resolved API key to the
///      attacker's host.
///   3. Adding `request_headers` that echo credentials into custom fields.
///
/// The sanitizer enforces a strict provider-level whitelist: only `name`,
/// `adapter`, `compatibility`, `docs_url`, `enabled`, and `models` survive.
/// `auth` is clamped to `api_key: none`. `base_url` and `request_headers`
/// are stripped outright — users who want to point a remote-defined provider
/// at a specific endpoint or inject custom headers must re-declare that
/// provider in their local `~/.glue/models.yaml`.
///
/// Output is YAML (not JSON): the cached file is what `glue catalog edit`
/// opens in `$EDITOR`, so preserving the upstream's block structure and
/// comments is worth the small edit-graph overhead.
library;

import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

const _allowedProviderFields = <String>{
  'name',
  'adapter',
  'compatibility',
  'docs_url',
  'enabled',
  'models',
};

String sanitizeRemoteCatalogYaml(String yaml) {
  final YamlEditor editor;
  try {
    editor = YamlEditor(yaml);
  } catch (_) {
    return yaml;
  }
  final root = editor.parseAt(const [], orElse: () => wrapAsYamlNode(null));
  if (root is! YamlMap) return yaml;
  final providers = root['providers'];
  if (providers is! YamlMap) return editor.toString();

  for (final pidKey in providers.keys) {
    final pid = pidKey.toString();
    final provider = providers[pidKey];
    if (provider is! YamlMap) continue;
    // Drop every field outside the whitelist (removes base_url,
    // request_headers, auth, and anything future we haven't vetted).
    final disallowed = provider.keys
        .map((k) => k.toString())
        .where((k) => !_allowedProviderFields.contains(k))
        .toList();
    for (final key in disallowed) {
      editor.remove(['providers', pid, key]);
    }
    // Auth is always clamped — remote catalogs cannot carry secrets.
    editor.update(['providers', pid, 'auth'], {'api_key': 'none'});
  }
  return editor.toString();
}
