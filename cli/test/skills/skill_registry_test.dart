import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:glue/src/skills/skill_parser.dart';
import 'package:glue/src/skills/skill_registry.dart';

void main() {
  group('SkillRegistry', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('skill_registry_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    void createSkill(String basePath, String name, {String? description}) {
      final dir = Directory(p.join(basePath, name));
      dir.createSync(recursive: true);
      File(p.join(dir.path, 'SKILL.md')).writeAsStringSync(
        '---\nname: $name\ndescription: ${description ?? "A $name skill."}\n---\nBody of $name.\n',
      );
    }

    test('discovers project-local skills', () {
      final skillsDir = p.join(tempDir.path, '.glue', 'skills');
      createSkill(skillsDir, 'my-skill');
      final registry = SkillRegistry.discover(cwd: tempDir.path);
      expect(registry.length, 1);
      expect(registry.list().first.name, 'my-skill');
      expect(registry.list().first.source, SkillSource.project);
    });

    test('discovers skills from extra paths', () {
      final extraDir = Directory(p.join(tempDir.path, 'extra-skills'));
      extraDir.createSync();
      createSkill(extraDir.path, 'extra-skill');
      final registry = SkillRegistry.discover(
        cwd: tempDir.path,
        extraPaths: [extraDir.path],
      );
      expect(registry.length, 1);
      expect(registry.list().first.name, 'extra-skill');
      expect(registry.list().first.source, SkillSource.custom);
    });

    test('project-local wins over extra on name collision', () {
      final projectDir = p.join(tempDir.path, '.glue', 'skills');
      createSkill(projectDir, 'dupe', description: 'Project version.');
      final extraDir = Directory(p.join(tempDir.path, 'extra'));
      extraDir.createSync();
      createSkill(extraDir.path, 'dupe', description: 'Extra version.');
      final registry = SkillRegistry.discover(
        cwd: tempDir.path,
        extraPaths: [extraDir.path],
      );
      expect(registry.length, 1);
      expect(registry.list().first.description, 'Project version.');
    });

    test('findByName returns correct skill', () {
      final skillsDir = p.join(tempDir.path, '.glue', 'skills');
      createSkill(skillsDir, 'alpha');
      createSkill(skillsDir, 'beta');
      final registry = SkillRegistry.discover(cwd: tempDir.path);
      expect(registry.findByName('alpha')?.name, 'alpha');
      expect(registry.findByName('beta')?.name, 'beta');
      expect(registry.findByName('gamma'), isNull);
    });

    test('loadBody returns skill body', () {
      final skillsDir = p.join(tempDir.path, '.glue', 'skills');
      createSkill(skillsDir, 'reader');
      final registry = SkillRegistry.discover(cwd: tempDir.path);
      final body = registry.loadBody('reader');
      expect(body, contains('Body of reader.'));
    });

    test('loadBody throws for unknown skill', () {
      final registry = SkillRegistry.discover(cwd: tempDir.path);
      expect(() => registry.loadBody('nope'), throwsA(isA<SkillParseError>()));
    });

    test('skips invalid skills silently', () {
      final skillsDir = p.join(tempDir.path, '.glue', 'skills');
      final dir = Directory(p.join(skillsDir, 'bad-skill'));
      dir.createSync(recursive: true);
      File(p.join(dir.path, 'SKILL.md')).writeAsStringSync('no frontmatter');
      createSkill(skillsDir, 'good-skill');
      final registry = SkillRegistry.discover(cwd: tempDir.path);
      expect(registry.length, 1);
      expect(registry.list().first.name, 'good-skill');
    });

    test('empty when no skills dirs exist', () {
      final registry = SkillRegistry.discover(cwd: tempDir.path);
      expect(registry.isEmpty, true);
    });

    test('discovers skill with lowercase skill.md', () {
      final skillsDir = p.join(tempDir.path, '.glue', 'skills');
      final dir = Directory(p.join(skillsDir, 'lower'));
      dir.createSync(recursive: true);
      File(p.join(dir.path, 'skill.md')).writeAsStringSync(
        '---\nname: lower\ndescription: Lowercase.\n---\nLower body.\n',
      );
      final registry = SkillRegistry.discover(cwd: tempDir.path);
      expect(registry.length, 1);
      expect(registry.list().first.description, 'Lowercase.');
    });
  });
}
