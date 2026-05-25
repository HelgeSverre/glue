import 'dart:io';

import 'package:glue_harness/glue_harness.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final bundledSkillsDir = Directory(p.join(Directory.current.path, 'skills'));

  Iterable<File> bundledSkillFiles() => bundledSkillsDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => p.basename(file.path).toLowerCase() == 'skill.md');

  test('bundled skills directory contains parseable builtins', () {
    expect(bundledSkillsDir.existsSync(), isTrue);

    final tempHome = Directory.systemTemp.createTempSync(
      'bundled_skills_home_',
    );
    addTearDown(() => tempHome.deleteSync(recursive: true));

    final registry = SkillRegistry.discover(
      cwd: Directory.current.path,
      home: tempHome.path,
      bundledPaths: [bundledSkillsDir.path],
    );

    expect(registry.length, greaterThanOrEqualTo(3));
    expect(
      registry.list().map((s) => s.source).toSet(),
      contains(SkillSource.bundled),
    );
    expect(registry.findByName('code-review'), isNotNull);
    expect(registry.findByName('agentic-research'), isNotNull);
  });

  test('bundled skills have unique names and non-empty bodies', () {
    final skillFiles = bundledSkillFiles().toList(growable: false);
    expect(skillFiles, isNotEmpty);

    final seenNames = <String>{};
    for (final skillFile in skillFiles) {
      final content = skillFile.readAsStringSync();
      final meta = parseSkillFrontmatter(
        content,
        p.dirname(skillFile.path),
        skillFile.path,
        SkillSource.bundled,
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
    final linkPattern = RegExp(r'\[[^\]]+\]\(([^)]+)\)');

    for (final skillFile in bundledSkillFiles()) {
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

        final resolvedPath = p.normalize(
          p.join(p.dirname(skillFile.path), pathOnly),
        );
        final exists =
            FileSystemEntity.typeSync(resolvedPath) !=
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
