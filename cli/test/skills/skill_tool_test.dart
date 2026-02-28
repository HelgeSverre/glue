import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/skills/skill_tool.dart';
import 'package:glue/src/skills/skill_registry.dart';

void main() {
  group('SkillTool', () {
    late Directory tempDir;
    late SkillRegistry registry;
    late SkillTool tool;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('skill_tool_test_');
      final skillsDir = p.join(tempDir.path, '.glue', 'skills');

      for (final name in ['code-review', 'tdd']) {
        final dir = Directory(p.join(skillsDir, name));
        dir.createSync(recursive: true);
        File(p.join(dir.path, 'SKILL.md')).writeAsStringSync(
          '---\nname: $name\ndescription: The $name skill.\n---\n\n'
          '# $name\n\nInstructions for $name.\n',
        );
      }

      registry = SkillRegistry.discover(cwd: tempDir.path, home: tempDir.path);
      tool = SkillTool(registry);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('name is skill', () {
      expect(tool.name, 'skill');
    });

    test('has optional name parameter', () {
      expect(tool.parameters.length, 1);
      expect(tool.parameters.first.name, 'name');
      expect(tool.parameters.first.required, false);
    });

    test('list skills when no name provided', () async {
      final result = ContentPart.textOnly(await tool.execute({}));
      expect(result, contains('Available skills'));
      expect(result, contains('code-review'));
      expect(result, contains('tdd'));
    });

    test('list skills when name is empty', () async {
      final result = ContentPart.textOnly(await tool.execute({'name': ''}));
      expect(result, contains('Available skills'));
    });

    test('activate skill returns body', () async {
      final result = ContentPart.textOnly(await tool.execute({'name': 'code-review'}));
      expect(result, contains('# Skill: code-review'));
      expect(result, contains('Instructions for code-review'));
    });

    test('activate unknown skill returns error', () async {
      final result = ContentPart.textOnly(await tool.execute({'name': 'nonexistent'}));
      expect(result, contains('Error'));
      expect(result, contains('not found'));
    });

    test('empty registry returns helpful message', () async {
      final emptyDir = Directory.systemTemp.createTempSync('skill_tool_empty_');
      final emptyRegistry =
          SkillRegistry.discover(cwd: emptyDir.path, home: emptyDir.path);
      final emptyTool = SkillTool(emptyRegistry);
      final result = ContentPart.textOnly(await emptyTool.execute({}));
      expect(result, contains('No skills available'));
      emptyDir.deleteSync(recursive: true);
    });
  });
}
