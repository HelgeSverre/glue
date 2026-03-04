import 'package:glue/src/core/environment.dart';
import 'package:glue/src/skills/skill_parser.dart';
import 'package:glue/src/skills/skill_registry.dart';

typedef SkillPathsProvider = List<String> Function();

/// Session-scoped skill discovery/runtime facade.
///
/// Keeps a live [SkillRegistry] and supports refresh-on-demand so all
/// skill entry points (`/skills` panel and `skill` tool) can stay in sync.
class SkillRuntime {
  final String cwd;
  final SkillPathsProvider extraPathsProvider;
  final Environment environment;

  late SkillRegistry _registry;

  SkillRuntime({
    required this.cwd,
    required this.extraPathsProvider,
    String? home,
    Environment? environment,
  }) : environment = _resolveEnvironment(
          cwd: cwd,
          home: home,
          environment: environment,
        ) {
    _registry = SkillRegistry.discover(
      cwd: cwd,
      extraPaths: extraPathsProvider(),
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
