import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:glue/src/skills/skill_registry.dart';
import 'package:glue/src/skills/skill_parser.dart';

void main() {
  test('bundled skills directory contains parseable builtins', () {
    final bundledDir = p.join(Directory.current.path, 'skills');
    expect(Directory(bundledDir).existsSync(), isTrue);

    final tempHome =
        Directory.systemTemp.createTempSync('bundled_skills_home_');
    addTearDown(() => tempHome.deleteSync(recursive: true));

    final registry = SkillRegistry.discover(
      cwd: Directory.current.path,
      home: tempHome.path,
      bundledPaths: [bundledDir],
    );

    expect(registry.length, greaterThanOrEqualTo(5));
    expect(
      registry.list().map((s) => s.source).toSet(),
      contains(SkillSource.custom),
    );
    expect(registry.findByName('code-review'), isNotNull);
    expect(registry.findByName('agentic-research'), isNotNull);
  });
}
