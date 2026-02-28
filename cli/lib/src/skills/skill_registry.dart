import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:glue/src/skills/skill_parser.dart';

class SkillRegistry {
  final List<SkillMeta> _skills;
  final Map<String, SkillMeta> _byName;

  SkillRegistry._(this._skills)
      : _byName = {for (final s in _skills) s.name: s};

  factory SkillRegistry.discover({
    required String cwd,
    List<String> extraPaths = const [],
    String? home,
  }) {
    final skills = <SkillMeta>[];
    final seen = <String>{};

    void scanDir(String dirPath, SkillSource source) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return;
      try {
        for (final entry in dir.listSync()) {
          if (entry is! Directory) continue;
          File? skillFile;
          final upper = File(p.join(entry.path, 'SKILL.md'));
          final lower = File(p.join(entry.path, 'skill.md'));
          if (upper.existsSync()) {
            skillFile = upper;
          } else if (lower.existsSync()) {
            skillFile = lower;
          }
          if (skillFile == null) continue;

          try {
            final content = skillFile.readAsStringSync();
            final meta = parseSkillFrontmatter(
              content,
              entry.path,
              skillFile.path,
              source,
            );
            if (!seen.contains(meta.name)) {
              seen.add(meta.name);
              skills.add(meta);
            }
          } on SkillParseError {
            // Skip invalid skills silently
          }
        }
      } on FileSystemException {
        // Directory not readable
      }
    }

    scanDir(p.join(cwd, '.glue', 'skills'), SkillSource.project);

    home ??= Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty) {
      scanDir(p.join(home, '.glue', 'skills'), SkillSource.global);
    }

    for (final extra in extraPaths) {
      final resolved =
          extra.startsWith('~') ? p.join(home, extra.substring(1)) : extra;
      scanDir(resolved, SkillSource.custom);
    }

    return SkillRegistry._(skills);
  }

  List<SkillMeta> list() => List.unmodifiable(_skills);

  SkillMeta? findByName(String name) => _byName[name];

  String loadBody(String name) {
    final meta = _byName[name];
    if (meta == null) throw SkillParseError('Skill not found: $name');
    return loadSkillBody(meta.skillMdPath);
  }

  bool get isEmpty => _skills.isEmpty;
  int get length => _skills.length;
}
