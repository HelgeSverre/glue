/// Pure-function candidate producers for slash-command argument
/// autocomplete. The App class wires these into
/// [SlashCommandRegistry.attachArgCompleter] after pulling the required
/// live state (catalog, skill list) out of its own fields.
///
/// Keeping the logic here — as pure functions that take their inputs by
/// parameter — means tests can exercise the same code path that runs in
/// production without spinning up a full `App`.
library;

import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/runtime/services/config.dart';
import 'package:glue/src/skills/skill_parser.dart';
import 'package:glue/src/skills/skill_runtime.dart';

const Map<String, String> openTargets = {
  'home': r'$GLUE_HOME',
  'session': 'current session folder',
  'sessions': 'all sessions',
  'logs': 'logs/',
  'skills': 'skills/',
  'plans': 'plans/',
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

// -----------------------------------------------------------------------
// Closure factories
//
// Each factory below returns an [ArgCompleter] bound to the live state
// it needs (catalog snapshot, skill registry). Slash-command modules in
// `runtime/commands/register_builtin_slash_commands.dart` call these in
// `attachArgCompleters()` instead of each controller carrying a
// forwarding method.
// -----------------------------------------------------------------------

ArgCompleter modelArgCompleter(Config config) => (prior, partial) {
      if (prior.isNotEmpty) return const [];
      final cfg = config.current;
      if (cfg == null) return const [];
      return modelRefCandidates(cfg.catalogData.providers, partial);
    };

ArgCompleter skillsArgCompleter(SkillRuntime skillRuntime) => (prior, partial) {
      if (prior.isNotEmpty) return const [];
      return skillCandidates(skillRuntime.list(), partial);
    };

ArgCompleter sessionArgCompleter() => sessionArgCandidates;

ArgCompleter providerArgCompleter(Config config) => (prior, partial) {
      if (prior.isEmpty) return providerSubcommandCandidates(partial);
      if (prior.length == 1 &&
          const {'add', 'remove', 'test'}.contains(prior.first)) {
        final cfg = config.current;
        if (cfg == null) return const [];
        return providerIdCandidates(cfg.catalogData.providers, partial);
      }
      return const [];
    };

ArgCompleter openArgCompleter() => openArgCandidates;

ArgCompleter shareArgCompleter() => shareArgCandidates;
