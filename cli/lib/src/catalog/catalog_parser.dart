/// Parses the Glue model/provider catalog YAML into [ModelCatalog].
///
/// The parser is forgiving about *extra* fields (forward-compat) but strict
/// about required ones — malformed catalogs raise [CatalogParseException] with
/// a path to the offending node.
library;

import 'package:yaml/yaml.dart';

import 'package:glue/src/catalog/model_catalog.dart';

class CatalogParseException implements Exception {
  CatalogParseException(this.message, {this.path});

  final String message;
  final String? path;

  @override
  String toString() => path == null
      ? 'CatalogParseException: $message'
      : 'CatalogParseException at $path: $message';
}

/// Parse a YAML string into a [ModelCatalog].
ModelCatalog parseCatalogYaml(String yaml) {
  final doc = loadYaml(yaml);
  if (doc is! Map) {
    throw CatalogParseException('catalog root must be a mapping');
  }
  return _parseCatalog(doc);
}

ModelCatalog _parseCatalog(Map<dynamic, dynamic> root) {
  final version = root['version'];
  if (version is! int) {
    throw CatalogParseException('version is required and must be an integer',
        path: 'version');
  }

  final defaults = _parseDefaults(root['defaults']);
  final capabilities = _parseCapabilities(root['capabilities']);
  final providers = _parseProviders(root['providers']);

  return ModelCatalog(
    version: version,
    updatedAt: root['updated_at']?.toString() ?? '',
    defaults: defaults,
    capabilities: capabilities,
    providers: providers,
  );
}

DefaultsConfig _parseDefaults(Object? node) {
  if (node is! Map) {
    throw CatalogParseException('defaults is required', path: 'defaults');
  }
  final model = node['model'];
  if (model is! String || model.isEmpty) {
    throw CatalogParseException(
      'defaults.model is required',
      path: 'defaults.model',
    );
  }
  return DefaultsConfig(
    model: model,
    smallModel: node['small_model']?.toString(),
    localModel: node['local_model']?.toString(),
  );
}

Map<String, String> _parseCapabilities(Object? node) {
  if (node == null) return const {};
  if (node is! Map) {
    throw CatalogParseException('capabilities must be a mapping',
        path: 'capabilities');
  }
  final out = <String, String>{};
  node.forEach((key, value) {
    out[key.toString()] = value?.toString() ?? '';
  });
  return out;
}

Map<String, ProviderDef> _parseProviders(Object? node) {
  if (node == null) return const {};
  if (node is! Map) {
    throw CatalogParseException('providers must be a mapping',
        path: 'providers');
  }
  final out = <String, ProviderDef>{};
  node.forEach((key, value) {
    final id = key.toString();
    out[id] = _parseProvider(id, value);
  });
  return out;
}

ProviderDef _parseProvider(String id, Object? node) {
  if (node is! Map) {
    throw CatalogParseException('provider must be a mapping',
        path: 'providers.$id');
  }

  final name = node['name']?.toString() ?? id;
  final adapter = node['adapter']?.toString();
  if (adapter == null || adapter.isEmpty) {
    throw CatalogParseException(
      'adapter is required',
      path: 'providers.$id.adapter',
    );
  }

  final auth = _parseAuth(node['auth'], path: 'providers.$id.auth');

  return ProviderDef(
    id: id,
    name: name,
    adapter: adapter,
    compatibility: node['compatibility']?.toString(),
    enabled: _asBool(node['enabled'], defaultValue: true),
    baseUrl: node['base_url']?.toString(),
    docsUrl: node['docs_url']?.toString(),
    auth: auth,
    requestHeaders: _parseStringMap(node['request_headers']),
    models: _parseModels(node['models'], providerId: id),
  );
}

AuthSpec _parseAuth(Object? node, {required String path}) {
  if (node is! Map) {
    throw CatalogParseException('auth is required', path: path);
  }

  final helpUrl = node['help_url']?.toString();

  // Explicit kind form (preferred for oauth): `auth: {kind: oauth, ...}`.
  final kindStr = node['kind']?.toString();
  if (kindStr != null) {
    switch (kindStr) {
      case 'oauth':
        return AuthSpec(kind: AuthKind.oauth, helpUrl: helpUrl);
      case 'api_key':
        final envVar = _extractEnvVar(node['api_key']?.toString(), path);
        return AuthSpec(
          kind: AuthKind.apiKey,
          envVar: envVar,
          helpUrl: helpUrl,
        );
      case 'none':
        return AuthSpec(kind: AuthKind.none, helpUrl: helpUrl);
      default:
        throw CatalogParseException(
          'auth.kind must be one of: api_key, oauth, none (got "$kindStr")',
          path: '$path.kind',
        );
    }
  }

  // Shorthand form: `auth: {api_key: env:NAME}` or `auth: {api_key: none}`.
  final raw = node['api_key']?.toString();
  if (raw == null || raw.isEmpty) {
    throw CatalogParseException('auth.api_key is required',
        path: '$path.api_key');
  }
  if (raw == 'none') {
    return AuthSpec(kind: AuthKind.none, helpUrl: helpUrl);
  }
  if (raw.startsWith('env:')) {
    final envVar = _extractEnvVar(raw, path);
    return AuthSpec(
      kind: AuthKind.apiKey,
      envVar: envVar,
      helpUrl: helpUrl,
    );
  }
  throw CatalogParseException(
    'auth.api_key must be one of: env:NAME, none (got "$raw"). '
    'For oauth providers use `auth: {kind: oauth}`. '
    'Inline API keys belong in ~/.glue/credentials.json, not the catalog.',
    path: '$path.api_key',
  );
}

String? _extractEnvVar(String? raw, String path) {
  if (raw == null || !raw.startsWith('env:')) return null;
  final envVar = raw.substring(4).trim();
  if (envVar.isEmpty) {
    throw CatalogParseException(
      'env: must name an environment variable',
      path: '$path.api_key',
    );
  }
  return envVar;
}

Map<String, String> _parseStringMap(Object? node) {
  if (node == null) return const {};
  if (node is! Map) return const {};
  final out = <String, String>{};
  node.forEach((key, value) {
    out[key.toString()] = value?.toString() ?? '';
  });
  return out;
}

Map<String, ModelDef> _parseModels(Object? node, {required String providerId}) {
  if (node == null) return const {};
  if (node is! Map) {
    throw CatalogParseException(
      'models must be a mapping',
      path: 'providers.$providerId.models',
    );
  }
  final out = <String, ModelDef>{};
  node.forEach((key, value) {
    final id = key.toString();
    out[id] = _parseModel(id, value, providerId: providerId);
  });
  return out;
}

ModelDef _parseModel(String id, Object? node, {required String providerId}) {
  if (node is! Map) {
    throw CatalogParseException(
      'model must be a mapping',
      path: 'providers.$providerId.models.$id',
    );
  }
  final capabilities = <String>{};
  final capNode = node['capabilities'];
  if (capNode is Iterable) {
    for (final cap in capNode) {
      capabilities.add(cap.toString());
    }
  }
  return ModelDef(
    id: id,
    name: node['name']?.toString() ?? id,
    apiId: node['api_id']?.toString(),
    recommended: _asBool(node['recommended']),
    isDefault: _asBool(node['default']),
    capabilities: capabilities,
    contextWindow: _asInt(node['context_window']),
    maxOutputTokens: _asInt(node['max_output_tokens']),
    speed: node['speed']?.toString(),
    cost: node['cost']?.toString(),
    notes: node['notes']?.toString(),
  );
}

bool _asBool(Object? node, {bool defaultValue = false}) {
  if (node == null) return defaultValue;
  if (node is bool) return node;
  final s = node.toString().toLowerCase();
  if (s == 'true' || s == 'yes') return true;
  if (s == 'false' || s == 'no') return false;
  return defaultValue;
}

int? _asInt(Object? node) {
  if (node == null) return null;
  if (node is int) return node;
  return int.tryParse(node.toString());
}
