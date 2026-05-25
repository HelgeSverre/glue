import 'dart:io';

import 'package:glue_harness/glue_harness.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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

    SkillRegistry discover({
      String? home,
      List<String> extraPaths = const [],
      List<String> bundledPaths = const [],
    }) {
      return SkillRegistry.discover(
        cwd: tempDir.path,
        home: home ?? tempDir.path,
        extraPaths: extraPaths,
        bundledPaths: bundledPaths,
      );
    }

    test('discovers project-local skills', () {
      final skillsDir = p.join(tempDir.path, '.glue', 'skills');
      createSkill(skillsDir, 'my-skill');

      final registry = discover();

      expect(registry.length, 1);
      expect(registry.list().first.name, 'my-skill');
      expect(registry.list().first.source, SkillSource.project);
    });

    test('discovers skills from extra paths', () {
      final extraDir = Directory(p.join(tempDir.path, 'extra-skills'));
      extraDir.createSync();
      createSkill(extraDir.path, 'extra-skill');

      final registry = discover(extraPaths: [extraDir.path]);

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

      final registry = discover(extraPaths: [extraDir.path]);

      expect(registry.length, 1);
      expect(registry.list().first.description, 'Project version.');
    });

    test('custom wins over global on name collision', () {
      final homeDir = Directory(p.join(tempDir.path, 'home'))..createSync();
      final globalDir = p.join(homeDir.path, '.glue', 'skills');
      createSkill(globalDir, 'dupe', description: 'Global version.');
      final extraDir = Directory(p.join(tempDir.path, 'extra'));
      extraDir.createSync();
      createSkill(extraDir.path, 'dupe', description: 'Custom version.');

      final registry = discover(
        home: homeDir.path,
        extraPaths: [extraDir.path],
      );

      expect(registry.length, 1);
      expect(registry.list().first.description, 'Custom version.');
      expect(registry.list().first.source, SkillSource.custom);
    });

    test('global wins over bundled on name collision', () {
      final homeDir = Directory(p.join(tempDir.path, 'home'))..createSync();
      final globalDir = p.join(homeDir.path, '.glue', 'skills');
      createSkill(globalDir, 'dupe', description: 'Global version.');
      final bundledDir = Directory(p.join(tempDir.path, 'bundled-skills'));
      bundledDir.createSync();
      createSkill(bundledDir.path, 'dupe', description: 'Bundled version.');

      final registry = discover(
        home: homeDir.path,
        bundledPaths: [bundledDir.path],
      );

      expect(registry.length, 1);
      expect(registry.list().first.description, 'Global version.');
      expect(registry.list().first.source, SkillSource.global);
    });

    test('findByName returns correct skill', () {
      final skillsDir = p.join(tempDir.path, '.glue', 'skills');
      createSkill(skillsDir, 'alpha');
      createSkill(skillsDir, 'beta');

      final registry = discover();

      expect(registry.findByName('alpha')?.name, 'alpha');
      expect(registry.findByName('beta')?.name, 'beta');
      expect(registry.findByName('gamma'), isNull);
    });

    test('loadBody returns skill body', () {
      final skillsDir = p.join(tempDir.path, '.glue', 'skills');
      createSkill(skillsDir, 'reader');

      final registry = discover();
      final body = registry.loadBody('reader');

      expect(body, contains('Body of reader.'));
    });

    test('loadBody throws for unknown skill', () {
      final registry = discover();
      expect(() => registry.loadBody('nope'), throwsA(isA<SkillParseError>()));
    });

    test('records diagnostics for invalid skills', () {
      final skillsDir = p.join(tempDir.path, '.glue', 'skills');
      final dir = Directory(p.join(skillsDir, 'bad-skill'));
      dir.createSync(recursive: true);
      File(p.join(dir.path, 'SKILL.md')).writeAsStringSync('no frontmatter');
      createSkill(skillsDir, 'good-skill');

      final registry = discover();

      expect(registry.length, 1);
      expect(registry.list().first.name, 'good-skill');
      expect(registry.diagnostics(), hasLength(1));
      expect(registry.diagnostics().first.code, 'invalid-skill');
    });

    test('empty when no skills dirs exist', () {
      final registry = discover();
      expect(registry.isEmpty, true);
    });

    test('discovers skill with lowercase skill.md', () {
      final skillsDir = p.join(tempDir.path, '.glue', 'skills');
      final dir = Directory(p.join(skillsDir, 'lower'));
      dir.createSync(recursive: true);
      File(p.join(dir.path, 'skill.md')).writeAsStringSync(
        '---\nname: lower\ndescription: Lowercase.\n---\nLower body.\n',
      );

      final registry = discover();

      expect(registry.length, 1);
      expect(registry.list().first.description, 'Lowercase.');
    });

    test('discovers bundled skills', () {
      final bundledDir = Directory(p.join(tempDir.path, 'bundled-skills'));
      bundledDir.createSync();
      createSkill(bundledDir.path, 'builtin-one');

      final registry = discover(bundledPaths: [bundledDir.path]);

      expect(registry.length, 1);
      expect(registry.list().first.name, 'builtin-one');
      expect(registry.list().first.source, SkillSource.bundled);
    });

    test('discovers portable project and user skill paths', () {
      createSkill(p.join(tempDir.path, '.agents', 'skills'), 'portable');
      final homeDir = Directory(p.join(tempDir.path, 'home'))..createSync();
      createSkill(p.join(homeDir.path, '.agents', 'skills'), 'user-portable');
      createSkill(p.join(homeDir.path, '.claude', 'skills'), 'user-claude');

      final registry = discover(home: homeDir.path);

      expect(
        registry.findByName('portable')?.source,
        SkillSource.projectAgents,
      );
      expect(
        registry.findByName('user-portable')?.source,
        SkillSource.userAgents,
      );
      expect(
        registry.findByName('user-claude')?.source,
        SkillSource.userClaude,
      );
    });

    test('project native wins over project portable and claude skills', () {
      createSkill(
        p.join(tempDir.path, '.glue', 'skills'),
        'dupe',
        description: 'Project native.',
      );
      createSkill(
        p.join(tempDir.path, '.agents', 'skills'),
        'dupe',
        description: 'Project portable.',
      );
      createSkill(
        p.join(tempDir.path, '.claude', 'skills'),
        'dupe',
        description: 'Project Claude.',
      );

      final registry = discover();

      expect(registry.list(), hasLength(1));
      expect(registry.list().first.description, 'Project native.');
      expect(registry.list().first.source, SkillSource.project);
      expect(
        registry.diagnostics().where((d) => d.code == 'skill-shadowed'),
        hasLength(2),
      );
    });

    test('project portable wins over project claude skills', () {
      createSkill(
        p.join(tempDir.path, '.agents', 'skills'),
        'dupe',
        description: 'Project portable.',
      );
      createSkill(
        p.join(tempDir.path, '.claude', 'skills'),
        'dupe',
        description: 'Project Claude.',
      );

      final registry = discover();

      expect(registry.list(), hasLength(1));
      expect(registry.list().first.description, 'Project portable.');
      expect(registry.list().first.source, SkillSource.projectAgents);
    });

    test('configured paths win over user native skills', () {
      final extraDir = Directory(p.join(tempDir.path, 'extra'))..createSync();
      createSkill(extraDir.path, 'dupe', description: 'Configured.');
      final homeDir = Directory(p.join(tempDir.path, 'home'))..createSync();
      createSkill(
        p.join(homeDir.path, '.glue', 'skills'),
        'dupe',
        description: 'User native.',
      );

      final registry = discover(
        home: homeDir.path,
        extraPaths: [extraDir.path],
      );

      expect(registry.list(), hasLength(1));
      expect(registry.list().first.description, 'Configured.');
      expect(registry.list().first.source, SkillSource.custom);
    });

    test(
      'project portable skills win over user skills and record collision',
      () {
        createSkill(
          p.join(tempDir.path, '.agents', 'skills'),
          'dupe',
          description: 'Project portable.',
        );
        final homeDir = Directory(p.join(tempDir.path, 'home'))..createSync();
        createSkill(
          p.join(homeDir.path, '.glue', 'skills'),
          'dupe',
          description: 'User native.',
        );

        final registry = discover(home: homeDir.path);

        expect(registry.list(), hasLength(1));
        expect(registry.list().first.description, 'Project portable.');
        expect(
          registry.diagnostics().map((d) => d.code),
          contains('skill-shadowed'),
        );
      },
    );

    test('records resource metadata for discovered skills', () {
      final skillsDir = p.join(tempDir.path, '.glue', 'skills');
      createSkill(skillsDir, 'with-resources');
      final scriptsDir = Directory(
        p.join(skillsDir, 'with-resources', 'scripts'),
      )..createSync(recursive: true);
      File(p.join(scriptsDir.path, 'run.sh')).writeAsStringSync('echo hi');

      final registry = discover();

      final resources = registry.findByName('with-resources')!.resources;
      expect(resources, hasLength(1));
      expect(resources.first.relativePath, p.join('scripts', 'run.sh'));
      expect(resources.first.kind, SkillResourceKind.script);
      expect(resources.first.sizeBytes, greaterThan(0));
    });

    test('resource metadata is capped and reports truncation', () {
      final skillsDir = p.join(tempDir.path, '.glue', 'skills');
      createSkill(skillsDir, 'many-resources');
      final scriptsDir = Directory(
        p.join(skillsDir, 'many-resources', 'scripts'),
      )..createSync(recursive: true);
      for (var i = 0; i < 105; i++) {
        File(p.join(scriptsDir.path, 'script-$i.sh')).writeAsStringSync('x');
      }

      final registry = discover();

      expect(registry.findByName('many-resources')!.resources, hasLength(100));
      expect(
        registry.diagnostics().map((d) => d.code),
        contains('skill-resources-truncated'),
      );
    });

    test('skips hidden skill directories', () {
      final skillsDir = p.join(tempDir.path, '.glue', 'skills');
      final hiddenDir = Directory(p.join(skillsDir, '.system-skill'));
      hiddenDir.createSync(recursive: true);
      File(p.join(hiddenDir.path, 'SKILL.md')).writeAsStringSync(
        '---\nname: system-skill\ndescription: hidden\n---\nbody',
      );
      createSkill(skillsDir, 'visible-skill');

      final registry = discover();

      expect(registry.length, 1);
      expect(registry.list().first.name, 'visible-skill');
    });
  });
}
