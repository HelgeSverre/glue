import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:glue/src/skills/skill_runtime.dart';

void main() {
  group('SkillRuntime', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('skill_runtime_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    void createSkill(String basePath, String name, {String? body}) {
      final dir = Directory(p.join(basePath, name));
      dir.createSync(recursive: true);
      File(p.join(dir.path, 'SKILL.md')).writeAsStringSync(
        '---\nname: $name\ndescription: Desc for $name.\n---\n${body ?? "Body for $name."}\n',
      );
    }

    test('refresh sees newly added skills', () {
      final skillsDir = p.join(tempDir.path, '.glue', 'skills');
      createSkill(skillsDir, 'first');

      final runtime = SkillRuntime(
        cwd: tempDir.path,
        home: tempDir.path,
        extraPathsProvider: () => const [],
      );

      expect(runtime.list().map((s) => s.name), contains('first'));
      expect(runtime.list().map((s) => s.name), isNot(contains('second')));

      createSkill(skillsDir, 'second');
      runtime.refresh();
      expect(
          runtime.list().map((s) => s.name), containsAll(['first', 'second']));
    });

    test('loadBody can use refreshFirst', () {
      final runtime = SkillRuntime(
        cwd: tempDir.path,
        home: tempDir.path,
        extraPathsProvider: () => const [],
      );

      final skillsDir = p.join(tempDir.path, '.glue', 'skills');
      createSkill(skillsDir, 'reader', body: 'Special body.');

      final body = runtime.loadBody('reader', refreshFirst: true);
      expect(body, contains('Special body.'));
    });
  });
}
