import 'package:glue_harness/src/core/environment.dart';
import 'package:glue_harness/src/skills/skill_parser.dart';
import 'package:glue_harness/src/skills/skill_paths.dart';
import 'package:glue_harness/src/skills/skill_registry.dart';

typedef SkillPathsProvider = List<String> Function();

String skillDiscoveryHelpText() {
  return 'Glue discovers skills from:\n'
      '  .glue/skills/<skill-name>/SKILL.md (project native)\n'
      '  .agents/skills/<skill-name>/SKILL.md (project portable)\n'
      '  .claude/skills/<skill-name>/SKILL.md (project compatibility)\n'
      '  configured skill_paths (custom)\n'
      '  ~/.glue/skills/<skill-name>/SKILL.md (user native)\n'
      '  ~/.agents/skills/<skill-name>/SKILL.md (user portable)\n'
      '  ~/.claude/skills/<skill-name>/SKILL.md (user compatibility)\n'
      '  bundled Glue skills';
}

/// Session-scoped skill discovery/runtime facade.
///
/// Keeps a live [SkillRegistry] and supports refresh-on-demand so all
/// skill entry points (`/skills` panel and `skill` tool) can stay in sync.
class SkillRuntime {
  final String cwd;
  final SkillPathsProvider extraPathsProvider;
  final Environment environment;
  late final SkillPathsProvider bundledPathsProvider;

  late SkillRegistry _registry;

  SkillRuntime({
    required this.cwd,
    required this.extraPathsProvider,
    SkillPathsProvider? bundledPathsProvider,
    String? home,
    Environment? environment,
  }) : environment = Environment.resolve(
         cwd: cwd,
         home: home,
         environment: environment,
       ) {
    this.bundledPathsProvider =
        bundledPathsProvider ??
        () => discoverBundledSkillPaths(environment: this.environment.vars);
    _registry = SkillRegistry.discover(
      cwd: cwd,
      extraPaths: extraPathsProvider(),
      bundledPaths: this.bundledPathsProvider(),
      environment: this.environment,
    );
  }

  SkillRegistry get registry => _registry;

  /// Re-scan configured skill locations and replace the active registry.
  SkillRegistry refresh() {
    return _registry = SkillRegistry.discover(
      cwd: cwd,
      extraPaths: extraPathsProvider(),
      bundledPaths: bundledPathsProvider(),
      environment: environment,
    );
  }

  List<SkillMeta> list({bool refreshFirst = false}) {
    final reg = refreshFirst ? refresh() : _registry;
    return reg.list();
  }

  SkillMeta? findByName(String name, {bool refreshFirst = false}) {
    final reg = refreshFirst ? refresh() : _registry;
    return reg.findByName(name);
  }

  String loadBody(String name, {bool refreshFirst = false}) {
    final reg = refreshFirst ? refresh() : _registry;
    return reg.loadBody(name);
  }
}
