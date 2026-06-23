import 'dart:io';

import 'package:glue_strategies/glue_strategies.dart';
import 'package:path/path.dart' as p;

import 'package:glue_harness/src/core/environment.dart';
import 'package:glue_harness/src/skills/skill_parser.dart';

const _maxResourcesPerSkill = 100;

class SkillRegistry {
  final List<SkillMeta> _skills;
  final List<SkillDiagnostic> _diagnostics;
  final Map<String, SkillMeta> _byName;

  SkillRegistry._(this._skills, this._diagnostics)
    : _byName = {for (final s in _skills) s.name: s};

  factory SkillRegistry.discover({
    required String cwd,
    List<String> extraPaths = const [],
    List<String> bundledPaths = const [],
    String? home,
    Environment? environment,
  }) {
    final env = Environment.resolve(
      cwd: cwd,
      home: home,
      environment: environment,
    );
    final resolvedHome = env.home;

    final skills = <SkillMeta>[];
    final diagnostics = <SkillDiagnostic>[];
    final seen = <String, SkillMeta>{};
    final scannedDirs = <String>{};

    void addDiagnostic(SkillDiagnostic diagnostic) {
      diagnostics.add(diagnostic);
    }

    void scanDir(String dirPath, SkillSource source) {
      final normalizedDirPath = p.normalize(p.absolute(dirPath));
      if (!scannedDirs.add(normalizedDirPath)) return;
      final dir = Directory(normalizedDirPath);
      if (!dir.existsSync()) return;
      try {
        final entries = dir.listSync().whereType<Directory>().toList(
          growable: false,
        )..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
        for (final entry in entries) {
          final name = p.basename(entry.path);
          if (name.startsWith('.')) continue;
          File? skillFile;
          final upper = File(p.join(entry.path, 'SKILL.md'));
          final lower = File(p.join(entry.path, 'skill.md'));
          if (upper.existsSync()) {
            skillFile = upper;
          } else if (lower.existsSync()) {
            skillFile = lower;
            addDiagnostic(
              SkillDiagnostic(
                severity: SkillDiagnosticSeverity.warning,
                code: 'lowercase-skill-file',
                message: 'Use SKILL.md for maximum cross-client portability.',
                path: lower.path,
              ),
            );
          }
          if (skillFile == null) continue;

          try {
            final content = skillFile.readAsStringSync();
            final parsed = parseSkillFrontmatter(
              content,
              entry.path,
              skillFile.path,
              source,
            );
            final resources = _discoverResources(entry.path);
            if (resources.truncated) {
              addDiagnostic(
                SkillDiagnostic(
                  severity: SkillDiagnosticSeverity.warning,
                  code: 'skill-resources-truncated',
                  message:
                      'Resource listing for "${parsed.name}" was truncated at $_maxResourcesPerSkill files.',
                  path: entry.path,
                  skillName: parsed.name,
                ),
              );
            }
            final meta = parsed.copyWith(resources: resources.resources);
            final existing = seen[meta.name];
            if (existing == null) {
              seen[meta.name] = meta;
              skills.add(meta);
            } else {
              addDiagnostic(
                SkillDiagnostic(
                  severity: SkillDiagnosticSeverity.warning,
                  code: 'skill-shadowed',
                  message:
                      'Skill "${meta.name}" from ${source.label} was shadowed by '
                      '${existing.source.label} at ${existing.skillDir}.',
                  path: meta.skillDir,
                  skillName: meta.name,
                ),
              );
            }
          } on SkillParseError catch (e) {
            addDiagnostic(
              SkillDiagnostic(
                severity: SkillDiagnosticSeverity.error,
                code: 'invalid-skill',
                message: e.message,
                path: skillFile.path,
                skillName: name,
              ),
            );
          } on FileSystemException catch (e) {
            addDiagnostic(
              SkillDiagnostic(
                severity: SkillDiagnosticSeverity.error,
                code: 'skill-read-failed',
                message: e.message,
                path: skillFile.path,
                skillName: name,
              ),
            );
          }
        }
      } on FileSystemException catch (e) {
        addDiagnostic(
          SkillDiagnostic(
            severity: SkillDiagnosticSeverity.warning,
            code: 'skill-dir-unreadable',
            message: e.message,
            path: normalizedDirPath,
          ),
        );
      }
    }

    // Precedence is first-seen-wins:
    // project native > project .agents > project .claude > configured paths >
    // user native > user .agents > user .claude > bundled.
    final discoveryRoots = [
      (path: p.join(cwd, '.glue', 'skills'), source: SkillSource.project),
      (
        path: p.join(cwd, '.agents', 'skills'),
        source: SkillSource.projectAgents,
      ),
      (
        path: p.join(cwd, '.claude', 'skills'),
        source: SkillSource.projectClaude,
      ),
      for (final extra in extraPaths)
        (path: _resolvePath(extra, resolvedHome), source: SkillSource.custom),
      if (resolvedHome.isNotEmpty) ...[
        (path: env.skillsDir, source: SkillSource.global),
        (
          path: p.join(resolvedHome, '.agents', 'skills'),
          source: SkillSource.userAgents,
        ),
        (
          path: p.join(resolvedHome, '.claude', 'skills'),
          source: SkillSource.userClaude,
        ),
      ],
      for (final bundled in bundledPaths)
        (path: bundled, source: SkillSource.bundled),
    ];
    for (final root in discoveryRoots) {
      scanDir(root.path, root.source);
    }

    return SkillRegistry._(skills, diagnostics);
  }

  List<SkillMeta> list() => List.unmodifiable(_skills);

  List<SkillDiagnostic> diagnostics() => List.unmodifiable(_diagnostics);

  SkillMeta? findByName(String name) => _byName[name];

  String loadBody(String name) {
    final meta = _byName[name];
    if (meta == null) throw SkillParseError('Skill not found: $name');
    return loadSkillBody(meta.skillMdPath);
  }

  bool get isEmpty => _skills.isEmpty;
  int get length => _skills.length;
}

String _resolvePath(String path, String home) =>
    expandUserPath(path, home: home);

_SkillResourceDiscovery _discoverResources(String skillDir) {
  final rootPath = _canonicalPath(skillDir);
  final resources = <SkillResource>[];
  var truncated = false;
  for (final entry in [
    (dir: 'scripts', kind: SkillResourceKind.script),
    (dir: 'references', kind: SkillResourceKind.reference),
    (dir: 'assets', kind: SkillResourceKind.asset),
  ]) {
    final root = Directory(p.join(skillDir, entry.dir));
    if (!root.existsSync()) continue;
    try {
      for (final entity
          in root
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()) {
        if (resources.length >= _maxResourcesPerSkill) {
          truncated = true;
          break;
        }
        final absolutePath = _canonicalPath(entity.path);
        if (!_isWithinRoot(absolutePath, rootPath)) continue;
        FileStat? stat;
        try {
          stat = entity.statSync();
        } on FileSystemException {
          stat = null;
        }
        resources.add(
          SkillResource(
            relativePath: p.relative(absolutePath, from: rootPath),
            absolutePath: absolutePath,
            kind: entry.kind,
            sizeBytes: stat?.size,
          ),
        );
      }
    } on FileSystemException {
      // Resource listing is best-effort; unreadable resource directories should
      // not make an otherwise valid skill unavailable.
    }
  }
  resources.sort((a, b) => a.relativePath.compareTo(b.relativePath));
  return _SkillResourceDiscovery(resources: resources, truncated: truncated);
}

String _canonicalPath(String path) {
  try {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      return Directory(path).resolveSymbolicLinksSync();
    }
    return File(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return p.normalize(p.absolute(path));
  }
}

bool _isWithinRoot(String child, String root) {
  return p.equals(child, root) || p.isWithin(root, child);
}

class _SkillResourceDiscovery {
  final List<SkillResource> resources;
  final bool truncated;

  const _SkillResourceDiscovery({
    required this.resources,
    required this.truncated,
  });
}
