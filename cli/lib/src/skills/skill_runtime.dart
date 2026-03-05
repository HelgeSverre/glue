import 'package:glue/src/core/environment.dart';
import 'package:glue/src/skills/skill_parser.dart';
import 'package:glue/src/skills/skill_paths.dart';
import 'package:glue/src/skills/skill_registry.dart';

typedef SkillPathsProvider = List<String> Function();

String skillDiscoveryHelpText() {
  return 'Glue discovers skills from:\n'
      '  .glue/skills/<skill-name>/SKILL.md (project-local)\n'
      '  ~/.glue/skills/<skill-name>/SKILL.md (global)\n'
      '  configured skill_paths (custom)\n'
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
  }) : environment = _resolveEnvironment(
          cwd: cwd,
          home: home,
          environment: environment,
        ) {
    this.bundledPathsProvider = bundledPathsProvider ??
        () => discoverBundledSkillPaths(environment: this.environment.vars);
    _registry = SkillRegistry.discover(
      cwd: cwd,
      extraPaths: extraPathsProvider(),
      bundledPaths: this.bundledPathsProvider(),
      environment: this.environment,
    );
  }

  static Environment _resolveEnvironment({
    required String cwd,
    String? home,
    Environment? environment,
  }) {
    if (environment != null) return environment;
    if (home != null) return Environment.test(home: home, cwd: cwd);
    return Environment.detect(cwd: cwd);
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
