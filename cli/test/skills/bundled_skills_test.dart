import 'dart:io';

import 'package:glue/src/skills/skill_parser.dart';
import 'package:glue/src/skills/skill_registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final bundledDir = p.join(Directory.current.path, 'skills');

  test('bundled skills directory contains parseable builtins', () {
    expect(Directory(bundledDir).existsSync(), isTrue);

    final tempHome =
        Directory.systemTemp.createTempSync('bundled_skills_home_');
    addTearDown(() => tempHome.deleteSync(recursive: true));

    final registry = SkillRegistry.discover(
      cwd: Directory.current.path,
      home: tempHome.path,
      bundledPaths: [bundledDir],
    );

    expect(registry.length, greaterThanOrEqualTo(3));
    expect(
      registry.list().map((s) => s.source).toSet(),
      contains(SkillSource.custom),
    );
    expect(registry.findByName('code-review'), isNotNull);
    expect(registry.findByName('agentic-research'), isNotNull);
  });

  test('bundled skills have unique names and non-empty bodies', () {
    final skillFiles = Directory(bundledDir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => p.basename(file.path).toLowerCase() == 'skill.md')
        .toList(growable: false);
    expect(skillFiles, isNotEmpty);

    final seenNames = <String>{};
    for (final skillFile in skillFiles) {
      final content = skillFile.readAsStringSync();
      final meta = parseSkillFrontmatter(
        content,
        p.dirname(skillFile.path),
        skillFile.path,
        SkillSource.custom,
      );
      final body = loadSkillBody(skillFile.path).trim();
      expect(
        seenNames.add(meta.name),
        isTrue,
        reason: 'Duplicate bundled skill name: ${meta.name}',
      );
      expect(
        body,
        isNotEmpty,
        reason: 'Bundled skill has empty body: ${skillFile.path}',
      );
    }
  });

  test('bundled skills have no broken relative markdown links', () {
    final skillFiles = Directory(bundledDir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => p.basename(file.path).toLowerCase() == 'skill.md');

    final linkPattern = RegExp(r'\[[^\]]+\]\(([^)]+)\)');

    for (final skillFile in skillFiles) {
      final content = skillFile.readAsStringSync();
      for (final match in linkPattern.allMatches(content)) {
        final link = match.group(1);
        if (link == null || link.isEmpty) continue;
        if (link.startsWith('http://') ||
            link.startsWith('https://') ||
            link.startsWith('#') ||
            link.startsWith('mailto:')) {
          continue;
        }

        final pathOnly = link.split('#').first;
        if (pathOnly.isEmpty) continue;

        final resolvedPath =
            p.normalize(p.join(p.dirname(skillFile.path), pathOnly));
        final exists = FileSystemEntity.typeSync(resolvedPath) !=
            FileSystemEntityType.notFound;

        expect(
          exists,
          isTrue,
          reason: 'Broken relative link in ${skillFile.path}: $link',
        );
      }
    }
  });
}
