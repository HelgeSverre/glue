/// Mutates the `mcp.servers.*` block of `config.yaml` while preserving
/// the user's comments, formatting, and key order.
///
/// Backed by `package:yaml_edit`, which performs surgical edits on the
/// original YAML source. Every mutation writes the file atomically via
/// `tmp + rename`, and re-parses the result through [parseMcpConfig]
/// before committing — if the edit would produce an unloadable file, the
/// original is restored and [McpConfigWriteError] is thrown.
library;

import 'dart:io';

import 'package:glue_harness/src/config/config_template.dart';
import 'package:glue_harness/src/config/mcp_config.dart';
import 'package:glue_harness/src/core/environment.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Thrown when the writer refuses an operation (duplicate id, missing id,
/// or post-mutation re-parse failure).
class McpConfigWriteError implements Exception {
  McpConfigWriteError(this.message);
  final String message;

  @override
  String toString() => 'McpConfigWriteError: $message';
}

class McpConfigWriter {
  McpConfigWriter(this.configPath, {Environment? environment})
    : _env = environment;

  /// Absolute path to the user's `config.yaml`.
  final String configPath;
  final Environment? _env;

  /// Returns true if `mcp.servers.<id>` exists in the on-disk YAML.
  bool hasServer(String id) {
    final editor = _openEditor();
    final servers = _serversMap(editor);
    return servers != null && servers.containsKey(id);
  }

  /// Writes a server entry under `mcp.servers.<id>`. Creates the `mcp:`
  /// and `mcp.servers:` blocks if missing. Throws if [spec.id] already
  /// exists and [overwrite] is `false`.
  ///
  /// Every path is a *scoped* edit of the `mcp.servers` subtree only. We
  /// never re-render or replace the whole `mcp:` block, so sibling keys
  /// (e.g. `mcp.tool_policy` — a security deny-list) and user comments are
  /// preserved. See the C2 regression tests in `mcp_config_writer_test.dart`.
  void addServer(McpServerSpec spec, {bool overwrite = false}) {
    final file = File(configPath);
    if (!file.existsSync()) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(buildConfigTemplate());
    }
    final original = file.readAsStringSync();
    final parsed = _tryParse(original);
    final rootIsMap = parsed is Map;
    final mcp = rootIsMap ? parsed['mcp'] : null;
    final servers = mcp is Map ? mcp['servers'] : null;

    if (servers is Map && servers.containsKey(spec.id) && !overwrite) {
      throw McpConfigWriteError(
        "Server '${spec.id}' already exists. Pass --force to overwrite.",
      );
    }

    final specMap = _specToYaml(spec);

    // Case A — `mcp.servers` already has a block-styled entry: splice the
    // new entry in beside it.
    if (servers is Map && servers.isNotEmpty) {
      _mutate(
        (editor) => editor.update([
          'mcp',
          'servers',
          spec.id,
        ], wrapAsYamlNode(specMap, collectionStyle: CollectionStyle.BLOCK)),
      );
      return;
    }

    // Case B — `mcp:` exists but `servers` is empty (`{}`), null, or the
    // key is absent: set the whole `servers` value in ONE update. This is
    // the fix for C2 — it touches only `mcp.servers`, leaving sibling
    // `mcp.*` keys and comments untouched.
    if (mcp is Map) {
      _mutate(
        (editor) => editor.update(
          ['mcp', 'servers'],
          wrapAsYamlNode({
            spec.id: specMap,
          }, collectionStyle: CollectionStyle.BLOCK),
        ),
      );
      return;
    }

    // Case C — no `mcp:` block at all, but the document root is a mapping:
    // add the whole `mcp.servers` subtree. yaml_edit leaves the rest of the
    // file (keys + comments) untouched.
    if (rootIsMap) {
      _mutate(
        (editor) => editor.update(
          ['mcp'],
          wrapAsYamlNode({
            'servers': {spec.id: specMap},
          }, collectionStyle: CollectionStyle.BLOCK),
        ),
      );
      return;
    }

    // Case D — empty or comments-only file (null/scalar root). yaml_edit
    // cannot add a key to a non-map root, so render the block through a
    // throwaway editor and append it. An append never deletes content.
    _bootstrapEmptyRoot(file, original, spec, specMap);
  }

  /// Appends a freshly rendered `mcp.servers.<id>` block to a file whose
  /// root is not a mapping (empty or comments-only).
  ///
  /// Rendering goes through a throwaway [YamlEditor] so scalar quoting and
  /// escaping match the incremental path exactly — a value containing a
  /// newline is quoted (the L4 fix), not splattered across lines.
  void _bootstrapEmptyRoot(
    File file,
    String original,
    McpServerSpec spec,
    Map<String, dynamic> specMap,
  ) {
    final gen = YamlEditor('mcp:\n  servers:\n');
    gen.update(
      ['mcp', 'servers'],
      wrapAsYamlNode({
        spec.id: specMap,
      }, collectionStyle: CollectionStyle.BLOCK),
    );
    final block = gen.toString();

    final suffix = original.isEmpty || original.endsWith('\n') ? '' : '\n';
    final sep = original.trim().isEmpty ? '' : '\n';
    final newContent = '$original$suffix$sep$block';

    _validateOrThrow(newContent);

    final tmp = File('$configPath.tmp');
    tmp.writeAsStringSync(newContent);
    tmp.renameSync(file.path);
  }

  Object? _tryParse(String yamlSource) {
    try {
      return loadYaml(yamlSource);
    } on Exception {
      return null;
    }
  }

  void _validateOrThrow(String yamlSource) {
    try {
      final parsed = loadYaml(yamlSource);
      final mcpSection = parsed is YamlMap ? parsed['mcp'] : null;
      parseMcpConfig(mcpSection, _env?.vars ?? Platform.environment);
    } on Exception catch (e) {
      throw McpConfigWriteError(
        'Refusing to write: result would not parse ($e).',
      );
    }
  }

  /// Removes `mcp.servers.<id>`. Throws if the id is not present.
  void removeServer(String id) {
    if (!hasServer(id)) {
      throw McpConfigWriteError("Server '$id' is not in config.yaml.");
    }
    _mutate((editor) => editor.remove(['mcp', 'servers', id]));
  }

  /// Sets `mcp.servers.<id>.enabled`. Throws if the id is not present.
  void setEnabled(String id, bool enabled) {
    if (!hasServer(id)) {
      throw McpConfigWriteError("Server '$id' is not in config.yaml.");
    }
    _mutate(
      (editor) => editor.update(['mcp', 'servers', id, 'enabled'], enabled),
    );
  }

  /// Updates a server's `auth`, `resource_metadata_url`, and
  /// `authorization_server` keys atomically. Used after a successful
  /// OAuth flow to (a) write back `auth: {kind: oauth}` when previously
  /// `none` and (b) cache the discovered URLs to skip rediscovery next
  /// session.
  ///
  /// Idempotent — re-running with the same arguments is a no-op modulo
  /// the file mtime.
  void updateAuth(
    String id, {
    required McpAuthSpec auth,
    Uri? resourceMetadataUrl,
    Uri? authorizationServer,
  }) {
    if (!hasServer(id)) {
      throw McpConfigWriteError("Server '$id' is not in config.yaml.");
    }
    _mutate((editor) {
      final authMap = _authToYaml(auth);
      if (authMap != null) {
        editor.update(['mcp', 'servers', id, 'auth'], authMap);
      } else {
        // McpNoAuth — remove any existing auth key. Safe if absent.
        try {
          editor.remove(['mcp', 'servers', id, 'auth']);
        } catch (_) {
          // No key to remove; that's fine.
        }
      }
      if (resourceMetadataUrl != null) {
        editor.update([
          'mcp',
          'servers',
          id,
          'resource_metadata_url',
        ], resourceMetadataUrl.toString());
      }
      if (authorizationServer != null) {
        editor.update([
          'mcp',
          'servers',
          id,
          'authorization_server',
        ], authorizationServer.toString());
      }
    });
  }

  // ─── internals ───────────────────────────────────────────────────────────

  /// Applies [op] to a `YamlEditor`, validates the result re-parses, then
  /// atomically writes via `tmp + rename`. Caller is responsible for any
  /// bootstrap — see [_bootstrapIfNeeded].
  void _mutate(void Function(YamlEditor) op) {
    final file = File(configPath);
    final original = file.readAsStringSync();
    final editor = YamlEditor(original);
    op(editor);
    final updated = editor.toString();
    _validateOrThrow(updated);

    final tmp = File('$configPath.tmp');
    tmp.writeAsStringSync(updated);
    tmp.renameSync(file.path);
  }

  YamlEditor _openEditor() {
    final file = File(configPath);
    final src = file.existsSync() ? file.readAsStringSync() : '';
    return YamlEditor(src);
  }

  Map<dynamic, dynamic> _root(YamlEditor editor) {
    final root = editor.parseAt(
      [],
      orElse: () => wrapAsYamlNode(<dynamic, dynamic>{}),
    );
    final value = root.value;
    return value is Map ? value : const <dynamic, dynamic>{};
  }

  Map<dynamic, dynamic>? _serversMap(YamlEditor editor) {
    final root = _root(editor);
    final mcp = root['mcp'];
    if (mcp is! Map) return null;
    final servers = mcp['servers'];
    return servers is Map ? servers : null;
  }

  /// Converts a typed [McpServerSpec] into the YAML-shaped map the parser
  /// expects. Used by yaml_edit on the incremental-add path (when the
  /// `mcp.servers` block already has at least one block-styled entry).
  /// First-server bootstraps use [_renderServerEntry] instead so we
  /// control the emitted style.
  Map<String, dynamic> _specToYaml(McpServerSpec spec) {
    final out = <String, dynamic>{};
    switch (spec) {
      case McpStdioServerSpec(
        :final command,
        :final args,
        :final env,
        :final workingDirectory,
      ):
        out['command'] = command;
        if (args.isNotEmpty) out['args'] = args;
        if (env.isNotEmpty) out['env'] = env;
        if (workingDirectory != null) {
          out['working_directory'] = workingDirectory;
        }
      case McpUrlServerSpec(
        :final url,
        :final auth,
        :final resourceMetadataUrl,
        :final authorizationServer,
      ):
        out['url'] = url.toString();
        final authMap = _authToYaml(auth);
        if (authMap != null) out['auth'] = authMap;
        if (resourceMetadataUrl != null) {
          out['resource_metadata_url'] = resourceMetadataUrl.toString();
        }
        if (authorizationServer != null) {
          out['authorization_server'] = authorizationServer.toString();
        }
    }
    if (!spec.enabled) out['enabled'] = false;
    if (spec.callTimeoutSeconds != null) {
      out['call_timeout_seconds'] = spec.callTimeoutSeconds;
    }
    return out;
  }

  Map<String, dynamic>? _authToYaml(McpAuthSpec auth) {
    return switch (auth) {
      McpNoAuth() => null,
      McpBearerAuth(:final token) => {'kind': 'bearer', 'token': ?token},
      McpOAuthAuth() => {'kind': 'oauth'},
    };
  }
}
