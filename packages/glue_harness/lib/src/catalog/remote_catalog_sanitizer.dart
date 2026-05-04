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
library;

import 'dart:convert';

import 'package:yaml/yaml.dart';

const _allowedProviderFields = <String>{
  'name',
  'adapter',
  'compatibility',
  'docs_url',
  'enabled',
  'models',
};

String sanitizeRemoteCatalogYaml(String yaml) {
  final doc = loadYaml(yaml);
  if (doc is! Map) return yaml;
  final sanitized = _deepCopy(doc) as Map;
  final providers = sanitized['providers'];
  if (providers is Map) {
    for (final entry in providers.entries) {
      final p = entry.value;
      if (p is! Map) continue;
      // Drop every field outside the whitelist (removes base_url,
      // request_headers, and anything future we haven't vetted).
      p.removeWhere((k, _) => !_allowedProviderFields.contains(k.toString()));
      // Auth is always clamped — remote catalogs cannot carry secrets.
      p['auth'] = {'api_key': 'none'};
    }
  }
  // JSON is a valid YAML subset — this output round-trips through loadYaml.
  return jsonEncode(sanitized);
}

Object? _deepCopy(Object? value) {
  if (value is Map) {
    final copy = <String, dynamic>{};
    value.forEach((k, v) => copy[k.toString()] = _deepCopy(v));
    return copy;
  }
  if (value is List) {
    return value.map(_deepCopy).toList();
  }
  return value;
}
