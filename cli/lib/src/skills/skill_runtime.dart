import 'dart:io';

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
  final String? home;

  SkillRegistry _registry;

  SkillRuntime({
    required this.cwd,
    required this.extraPathsProvider,
    this.home,
  }) : _registry = SkillRegistry.discover(
          cwd: cwd,
          extraPaths: extraPathsProvider(),
          home: home ?? Platform.environment['HOME'],
        );

  SkillRegistry get registry => _registry;

  /// Re-scan configured skill locations and replace the active registry.
  SkillRegistry refresh() {
    return _registry = SkillRegistry.discover(
      cwd: cwd,
      extraPaths: extraPathsProvider(),
      home: home ?? Platform.environment['HOME'],
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
