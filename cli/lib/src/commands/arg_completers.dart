/// Pure-function candidate producers for slash-command argument
/// autocomplete. The App class wires these into
/// [SlashCommandRegistry.attachArgCompleter] after pulling the required
/// live state (catalog, skill list) out of its own fields.
///
/// Keeping the logic here — as pure functions that take their inputs by
/// parameter — means tests can exercise the same code path that runs in
/// production without spinning up a full `App`.
library;

import 'package:glue_core/glue_core.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:glue_strategies/glue_strategies.dart';

const Map<String, String> openTargets = {
  'home': r'$GLUE_HOME',
  'session': 'current session folder',
  'sessions': 'all sessions',
  'logs': 'logs/',
  'skills': 'skills/',
  'cache': 'cache/',
};

List<SlashArgCandidate> openArgCandidates(
  List<String> prior,
  String partial,
) {
  if (prior.isNotEmpty) return const [];
  return openTargets.entries
      .where((e) => e.key.startsWith(partial))
      .map((e) => SlashArgCandidate(value: e.key, description: e.value))
      .toList();
}

const Map<String, String> providerSubcommands = {
  'list': 'Open provider panel',
  'add': 'Authenticate a provider',
  'remove': 'Forget stored credentials',
  'test': 'Validate a provider',
};

List<SlashArgCandidate> providerSubcommandCandidates(String partial) {
  return providerSubcommands.entries
      .where((e) => e.key.startsWith(partial))
      .map((e) => SlashArgCandidate(
            value: e.key,
            description: e.value,
            continues: e.key != 'list',
          ))
      .toList();
}

List<SlashArgCandidate> providerIdCandidates(
  Map<String, ProviderDef> providers,
  String partial,
) {
  return providers.values
      .where((p) => p.id.toLowerCase().startsWith(partial))
      .map((p) => SlashArgCandidate(value: p.id, description: p.name))
      .toList();
}

/// Default cap for [modelRefCandidates] — large enough to cover a full
/// filtered result set in the dropdown, small enough that a blank match
/// against a 500-model catalog doesn't stall rendering.
const int defaultModelResultCap = 20;

/// Searches the catalog by provider prefix, model id substring, model
/// display-name substring, or full-ref substring. Callers should gate
/// on non-empty [partial] (see `App._modelArgCandidates`).
List<SlashArgCandidate> modelRefCandidates(
  Map<String, ProviderDef> providers,
  String partial, {
  int cap = defaultModelResultCap,
}) {
  if (partial.isEmpty) return const [];
  final out = <SlashArgCandidate>[];
  for (final p in providers.values) {
    for (final m in p.models.values) {
      final ref = '${p.id}/${m.id}';
      final matches = p.id.toLowerCase().startsWith(partial) ||
          m.id.toLowerCase().contains(partial) ||
          m.name.toLowerCase().contains(partial) ||
          ref.toLowerCase().contains(partial);
      if (matches) {
        out.add(SlashArgCandidate(value: ref, description: m.name));
        if (out.length >= cap) return out;
      }
    }
  }
  return out;
}

List<SlashArgCandidate> skillCandidates(
  List<SkillMeta> skills,
  String partial,
) {
  return skills
      .where((s) => s.name.toLowerCase().startsWith(partial))
      .map((s) => SlashArgCandidate(
            value: s.name,
            description: s.description,
          ))
      .toList();
}

const Map<String, String> sessionSubcommands = {
  'copy': 'Copy session ID to clipboard',
};

const Map<String, String> shareFormats = {
  'html': 'Export HTML only',
  'md': 'Export Markdown only',
  'gist': 'Export Markdown and publish a gist with gh',
};

List<SlashArgCandidate> sessionArgCandidates(
  List<String> prior,
  String partial,
) {
  if (prior.isNotEmpty) return const [];
  return sessionSubcommands.entries
      .where((e) => e.key.startsWith(partial))
      .map((e) => SlashArgCandidate(value: e.key, description: e.value))
      .toList();
}

List<SlashArgCandidate> shareArgCandidates(
  List<String> prior,
  String partial,
) {
  if (prior.isNotEmpty) return const [];
  return shareFormats.entries
      .where((e) => e.key.startsWith(partial))
      .map((e) => SlashArgCandidate(value: e.key, description: e.value))
      .toList();
}

const Map<String, String> mcpSubcommands = {
  'list': 'Print servers as a text table',
  'tools': 'List one server\'s tools',
  'reconnect': 'Retry a dead/reconnecting server',
  'toggle': 'Session-scoped enable/disable',
  'auth': 'Manage credentials',
  'help': 'Subcommand cheatsheet',
};

const Map<String, String> mcpAuthSubcommands = {
  'login': 'Run OAuth flow (HTTP/WS only)',
  'logout': 'Forget stored credentials',
  'status': 'Show credential state per server',
};

List<SlashArgCandidate> mcpSubcommandCandidates(String partial) {
  return mcpSubcommands.entries
      .where((e) => e.key.startsWith(partial))
      .map((e) => SlashArgCandidate(
            value: e.key,
            description: e.value,
            continues: e.key != 'list' && e.key != 'help',
          ))
      .toList();
}

List<SlashArgCandidate> mcpAuthSubcommandCandidates(String partial) {
  return mcpAuthSubcommands.entries
      .where((e) => e.key.startsWith(partial))
      .map((e) => SlashArgCandidate(
            value: e.key,
            description: e.value,
            continues: e.key != 'status',
          ))
      .toList();
}

/// Completes server IDs from the live pool. When [requireRemote] is true,
/// stdio servers are filtered out — used for `auth login/logout` which only
/// applies to HTTP/WebSocket transports.
List<SlashArgCandidate> mcpServerIdCandidates(
  Iterable<McpServerSnapshot> servers,
  String partial, {
  bool requireRemote = false,
}) {
  final needle = partial.toLowerCase();
  return servers
      .where((s) =>
          (!requireRemote || s.spec is! McpStdioServerSpec) &&
          s.id.toLowerCase().startsWith(needle))
      .map((s) => SlashArgCandidate(
            value: s.id,
            description: _mcpKindLabel(s.spec),
          ))
      .toList();
}

String _mcpKindLabel(McpServerSpec spec) => switch (spec) {
      McpStdioServerSpec() => 'stdio',
      McpHttpServerSpec() => 'http+sse',
      McpWebSocketServerSpec() => 'websocket',
    };
