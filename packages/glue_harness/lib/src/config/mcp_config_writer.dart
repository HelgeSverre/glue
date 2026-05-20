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
  McpConfigWriter(this.configPath);

  /// Absolute path to the user's `config.yaml`.
  final String configPath;

  /// Returns true if `mcp.servers.<id>` exists in the on-disk YAML.
  bool hasServer(String id) {
    final editor = _openEditor();
    final servers = _serversMap(editor);
    return servers != null && servers.containsKey(id);
  }

  /// Writes a server entry under `mcp.servers.<id>`. Creates the `mcp:`
  /// and `mcp.servers:` blocks if missing. Throws if [spec.id] already
  /// exists and [overwrite] is `false`.
  void addServer(McpServerSpec spec, {bool overwrite = false}) {
    // Bootstrap path: when there's no existing `mcp.servers:` block (or it
    // exists but is empty), yaml_edit can't reliably emit a block-style
    // nested entry — it inherits flow style from the null/empty parent. To
    // produce clean block YAML for the user, render the whole block as
    // text on first write. yaml_edit takes over from the second server on.
    final preExisting = _bootstrapIfNeeded(spec);
    if (preExisting) {
      // mcp.servers existed and was non-empty — use yaml_edit.
      _mutate((editor) {
        final servers = _serversMap(editor)!;
        if (servers.containsKey(spec.id) && !overwrite) {
          throw McpConfigWriteError(
            "Server '${spec.id}' already exists. Pass --force to overwrite.",
          );
        }
        editor.update(
          ['mcp', 'servers', spec.id],
          wrapAsYamlNode(
            _specToYaml(spec),
            collectionStyle: CollectionStyle.BLOCK,
          ),
        );
      });
      return;
    }
    // We just bootstrapped the block with this spec already inside.
    if (overwrite) {
      // Overwrite-of-the-first-entry is a corner case: if the spec id
      // existed before the bootstrap path realized it, we'd have hit the
      // pre-existing branch. So nothing to do here.
    }
  }

  /// If `mcp.servers` already exists and is non-empty, returns true and
  /// leaves the file untouched (caller uses yaml_edit). Otherwise renders
  /// the full `mcp:\n  servers:\n    <id>:\n      ...` block as text,
  /// appends it (or replaces the existing empty block), writes, and
  /// returns false to signal the caller that the bootstrap path ran.
  bool _bootstrapIfNeeded(McpServerSpec spec) {
    final file = File(configPath);
    if (!file.existsSync()) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(buildConfigTemplate());
    }
    final original = file.readAsStringSync();
    final parsed = _tryParse(original);
    final mcp = parsed is Map ? parsed['mcp'] : null;
    final servers = mcp is Map ? mcp['servers'] : null;
    final hasNonEmptyServers = servers is Map && servers.isNotEmpty;

    if (hasNonEmptyServers) return true;

    final block = _renderServerBlock(spec);
    final String newContent;
    if (mcp is Map) {
      // `mcp:` exists but has no servers (servers: null or absent).
      // Re-emit as a fresh block right after the `mcp:` line.
      newContent = _replaceMcpBlock(original, block);
    } else {
      // No `mcp:` section at all — append.
      final suffix = original.endsWith('\n') ? '' : '\n';
      newContent = '$original$suffix\n$block';
    }

    // Round-trip guard.
    _validateOrThrow(newContent);

    final tmp = File('$configPath.tmp');
    tmp.writeAsStringSync(newContent);
    tmp.renameSync(file.path);
    return false;
  }

  /// Renders a single server entry as a top-level `mcp:\n  servers:\n    <id>:\n      ...`
  /// block in block YAML style.
  String _renderServerBlock(McpServerSpec spec) {
    final buf = StringBuffer('mcp:\n  servers:\n');
    buf.write(_renderServerEntry(spec, indent: '    '));
    return buf.toString();
  }

  /// Renders a single `<id>:\n  command: ...` entry indented by [indent].
  String _renderServerEntry(McpServerSpec spec, {required String indent}) {
    final lines = StringBuffer();
    final inner = '$indent  ';
    lines.writeln('$indent${spec.id}:');
    switch (spec) {
      case McpStdioServerSpec(
          :final command,
          :final args,
          :final env,
          :final workingDirectory,
        ):
        lines.writeln('${inner}command: ${_scalar(command)}');
        if (args.isNotEmpty) {
          lines.writeln('${inner}args:');
          for (final a in args) {
            lines.writeln('$inner  - ${_scalar(a)}');
          }
        }
        if (env.isNotEmpty) {
          lines.writeln('${inner}env:');
          for (final e in env.entries) {
            lines.writeln('$inner  ${e.key}: ${_scalar(e.value)}');
          }
        }
        if (workingDirectory != null) {
          lines.writeln(
            '${inner}working_directory: ${_scalar(workingDirectory)}',
          );
        }
      case McpHttpServerSpec(:final url, :final auth):
        lines.writeln('${inner}url: ${_scalar(url.toString())}');
        _writeAuth(lines, auth, indent: inner);
      case McpWebSocketServerSpec(:final url, :final auth):
        lines.writeln('${inner}url: ${_scalar(url.toString())}');
        _writeAuth(lines, auth, indent: inner);
    }
    if (!spec.enabled) lines.writeln('${inner}enabled: false');
    if (spec.callTimeoutSeconds != null) {
      lines.writeln('${inner}call_timeout_seconds: ${spec.callTimeoutSeconds}');
    }
    return lines.toString();
  }

  void _writeAuth(StringBuffer out, McpAuthSpec auth, {required String indent}) {
    switch (auth) {
      case McpNoAuth():
        return;
      case McpBearerAuth(:final token):
        out.writeln('${indent}auth:');
        out.writeln('$indent  kind: bearer');
        if (token != null) out.writeln('$indent  token: ${_scalar(token)}');
      case McpOAuthAuth():
        out.writeln('${indent}auth:');
        out.writeln('$indent  kind: oauth');
    }
  }

  /// Single-line scalar emitter with conservative quoting. Quotes only
  /// when the value would otherwise parse as a non-string (booleans,
  /// numbers, null) or starts with a YAML indicator.
  String _scalar(String value) {
    if (value.isEmpty) return '""';
    const reserved = {'true', 'false', 'null', 'yes', 'no', 'on', 'off', '~'};
    final needsQuote = reserved.contains(value.toLowerCase()) ||
        RegExp(r'^[-+]?\d').hasMatch(value) ||
        RegExp(r'''[:#'"\[\]{}|>*&!%@`]''').hasMatch(value);
    if (!needsQuote) return value;
    final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }

  /// Replace the empty `mcp:` (with `servers:` empty or absent) block
  /// with the rendered [block] text. Preserves everything before and
  /// after the `mcp:` block.
  String _replaceMcpBlock(String source, String block) {
    final lines = source.split('\n');
    final mcpIdx = lines.indexWhere((l) => l.startsWith('mcp:'));
    if (mcpIdx == -1) {
      final suffix = source.endsWith('\n') ? '' : '\n';
      return '$source$suffix\n$block';
    }
    var end = mcpIdx + 1;
    while (end < lines.length) {
      final l = lines[end];
      if (l.isEmpty || l.startsWith(' ') || l.startsWith('\t')) {
        end++;
      } else {
        break;
      }
    }
    final before = lines.sublist(0, mcpIdx).join('\n');
    final after = lines.sublist(end).join('\n');
    final beforeSep = before.isEmpty || before.endsWith('\n') ? '' : '\n';
    final afterSep = after.startsWith('\n') || after.isEmpty ? '' : '\n';
    return '$before$beforeSep$block$afterSep$after';
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
      parseMcpConfig(mcpSection, Platform.environment);
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
    _mutate((editor) => editor.update(
          ['mcp', 'servers', id, 'enabled'],
          enabled,
        ));
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
    final root =
        editor.parseAt([], orElse: () => wrapAsYamlNode(<dynamic, dynamic>{}));
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
      case McpHttpServerSpec(:final url, :final auth):
        out['url'] = url.toString();
        final authMap = _authToYaml(auth);
        if (authMap != null) out['auth'] = authMap;
      case McpWebSocketServerSpec(:final url, :final auth):
        out['url'] = url.toString();
        final authMap = _authToYaml(auth);
        if (authMap != null) out['auth'] = authMap;
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
      McpBearerAuth(:final token) => {
          'kind': 'bearer',
          if (token != null) 'token': token,
        },
      McpOAuthAuth() => {'kind': 'oauth'},
    };
  }
}
