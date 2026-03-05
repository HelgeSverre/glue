import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:glue/src/skills/skill_paths.dart';

void main() {
  group('discoverBundledSkillPaths', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('skill_paths_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('uses GLUE_BUNDLED_SKILLS_DIR when present', () {
      final bundled = Directory(p.join(tempDir.path, 'bundled'))..createSync();
      final found = discoverBundledSkillPaths(
        environment: {'GLUE_BUNDLED_SKILLS_DIR': bundled.path},
        scriptPath: '',
      );
      expect(found, contains(p.normalize(bundled.path)));
    });

    test('derives cli/skills from script path', () {
      final repoRoot = Directory(p.join(tempDir.path, 'repo'))..createSync();
      final cliSkills = Directory(p.join(repoRoot.path, 'cli', 'skills'))
        ..createSync(recursive: true);
      final scriptPath = p.join(repoRoot.path, 'bin', 'glue.dart');
      final found = discoverBundledSkillPaths(
        environment: const {},
        scriptPath: scriptPath,
      );
      expect(found, contains(p.normalize(cliSkills.path)));
    });
  });
}
