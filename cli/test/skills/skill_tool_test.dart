import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:glue/src/skills/skill_tool.dart';
import 'package:glue/src/skills/skill_runtime.dart';

void main() {
  group('SkillTool', () {
    late Directory tempDir;
    late SkillRuntime runtime;
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

      runtime = SkillRuntime(
        cwd: tempDir.path,
        home: tempDir.path,
        extraPathsProvider: () => const [],
      );
      tool = SkillTool(runtime);
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
      final result = (await tool.execute({})).content;
      expect(result, contains('Available skills'));
      expect(result, contains('code-review'));
      expect(result, contains('tdd'));
    });

    test('list skills when name is empty', () async {
      final result = (await tool.execute({'name': ''})).content;
      expect(result, contains('Available skills'));
    });

    test('activate skill returns body', () async {
      final result = (await tool.execute({'name': 'code-review'})).content;
      expect(result, contains('# Skill: code-review'));
      expect(result, contains('Instructions for code-review'));
    });

    test('activate unknown skill returns error', () async {
      final result = (await tool.execute({'name': 'nonexistent'})).content;
      expect(result, contains('Error'));
      expect(result, contains('not found'));
    });

    test('empty registry returns helpful message', () async {
      final emptyDir = Directory.systemTemp.createTempSync('skill_tool_empty_');
      final emptyRuntime = SkillRuntime(
        cwd: emptyDir.path,
        home: emptyDir.path,
        extraPathsProvider: () => const [],
      );
      final emptyTool = SkillTool(emptyRuntime);
      final result = (await emptyTool.execute({})).content;
      expect(result, contains('No skills available'));
      expect(result, contains('bundled Glue skills'));
      emptyDir.deleteSync(recursive: true);
    });

    test('list reflects skills added after startup', () async {
      final result1 = (await tool.execute({})).content;
      expect(result1, isNot(contains('new-skill')));

      final skillsDir = p.join(tempDir.path, '.glue', 'skills');
      final newDir = Directory(p.join(skillsDir, 'new-skill'));
      newDir.createSync(recursive: true);
      File(p.join(newDir.path, 'SKILL.md')).writeAsStringSync(
        '---\nname: new-skill\ndescription: A new one.\n---\nBody.\n',
      );

      final result2 = (await tool.execute({})).content;
      expect(result2, contains('new-skill'));
    });

    test('shows custom source tag for bundled skills', () async {
      final bundledDir = Directory(p.join(tempDir.path, 'bundled'));
      final skillDir = Directory(p.join(bundledDir.path, 'builtin-skill'));
      skillDir.createSync(recursive: true);
      File(p.join(skillDir.path, 'SKILL.md')).writeAsStringSync(
        '---\nname: builtin-skill\ndescription: Built in.\n---\nBody.\n',
      );

      final builtinsRuntime = SkillRuntime(
        cwd: tempDir.path,
        home: tempDir.path,
        extraPathsProvider: () => const [],
        bundledPathsProvider: () => [bundledDir.path],
      );
      final builtinsTool = SkillTool(builtinsRuntime);

      final result = (await builtinsTool.execute({})).content;
      expect(result, contains('builtin-skill [custom]'));
    });
  });
}
