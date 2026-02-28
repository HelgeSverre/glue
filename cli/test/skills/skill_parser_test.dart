import 'package:test/test.dart';
import 'package:glue/src/skills/skill_parser.dart';

void main() {
  group('SkillMeta', () {
    test('stores all properties', () {
      final meta = SkillMeta(
        name: 'test',
        description: 'A test skill.',
        license: 'MIT',
        compatibility: 'any',
        allowedTools: 'Bash',
        metadata: {'author': 'me'},
        skillDir: '/s/test',
        skillMdPath: '/s/test/SKILL.md',
        source: SkillSource.project,
      );
      expect(meta.name, 'test');
      expect(meta.description, 'A test skill.');
      expect(meta.license, 'MIT');
      expect(meta.compatibility, 'any');
      expect(meta.allowedTools, 'Bash');
      expect(meta.metadata, {'author': 'me'});
      expect(meta.skillDir, '/s/test');
      expect(meta.skillMdPath, '/s/test/SKILL.md');
      expect(meta.source, SkillSource.project);
    });
  });

  group('parseSkillFrontmatter', () {
    test('parses valid minimal frontmatter', () {
      const content =
          '---\nname: my-skill\ndescription: A test skill.\n---\n\n# Instructions\nDo the thing.';
      final meta = parseSkillFrontmatter(
          content, '/path/to/my-skill', '/path/to/my-skill/SKILL.md',
          SkillSource.global);
      expect(meta.name, 'my-skill');
      expect(meta.description, 'A test skill.');
      expect(meta.license, isNull);
      expect(meta.source, SkillSource.global);
    });

    test('parses full frontmatter with all fields', () {
      const content =
          '---\nname: pdf-tool\ndescription: Process PDFs.\nlicense: MIT\ncompatibility: Requires poppler\nallowed-tools: Bash Read\nmetadata:\n  author: test-org\n  version: "1.0"\n---\nBody here.';
      final meta = parseSkillFrontmatter(
          content, '/skills/pdf-tool', '/skills/pdf-tool/SKILL.md',
          SkillSource.project);
      expect(meta.name, 'pdf-tool');
      expect(meta.description, 'Process PDFs.');
      expect(meta.license, 'MIT');
      expect(meta.compatibility, 'Requires poppler');
      expect(meta.allowedTools, 'Bash Read');
      expect(meta.metadata, {'author': 'test-org', 'version': '1.0'});
      expect(meta.source, SkillSource.project);
    });

    test('throws on missing frontmatter delimiter', () {
      expect(
          () => parseSkillFrontmatter(
              'no frontmatter', '/s/x', '/s/x/SKILL.md', SkillSource.global),
          throwsA(isA<SkillParseError>()));
    });

    test('throws on unclosed frontmatter', () {
      expect(
          () => parseSkillFrontmatter(
              '---\nname: x\n', '/s/x', '/s/x/SKILL.md', SkillSource.global),
          throwsA(isA<SkillParseError>()));
    });

    test('throws on missing name', () {
      expect(
          () => parseSkillFrontmatter('---\ndescription: foo\n---\nbody',
              '/s/x', '/s/x/SKILL.md', SkillSource.global),
          throwsA(isA<SkillParseError>()));
    });

    test('throws on missing description', () {
      expect(
          () => parseSkillFrontmatter('---\nname: x\n---\nbody', '/s/x',
              '/s/x/SKILL.md', SkillSource.global),
          throwsA(isA<SkillParseError>()));
    });

    test('throws on uppercase name', () {
      expect(
          () => parseSkillFrontmatter(
              '---\nname: MySkill\ndescription: foo\n---\n',
              '/s/MySkill',
              '/s/MySkill/SKILL.md',
              SkillSource.global),
          throwsA(isA<SkillParseError>()));
    });

    test('throws on name with consecutive hyphens', () {
      expect(
          () => parseSkillFrontmatter(
              '---\nname: my--skill\ndescription: foo\n---\n',
              '/s/my--skill',
              '/s/my--skill/SKILL.md',
              SkillSource.global),
          throwsA(isA<SkillParseError>()));
    });

    test('throws on name starting with hyphen', () {
      expect(
          () => parseSkillFrontmatter(
              '---\nname: -skill\ndescription: foo\n---\n',
              '/s/-skill',
              '/s/-skill/SKILL.md',
              SkillSource.global),
          throwsA(isA<SkillParseError>()));
    });

    test('throws on name not matching directory', () {
      expect(
          () => parseSkillFrontmatter(
              '---\nname: skill-a\ndescription: foo\n---\n',
              '/s/skill-b',
              '/s/skill-b/SKILL.md',
              SkillSource.global),
          throwsA(isA<SkillParseError>()));
    });

    test('throws on name exceeding 64 chars', () {
      final longName = 'a' * 65;
      expect(
          () => parseSkillFrontmatter(
              '---\nname: $longName\ndescription: foo\n---\n',
              '/s/$longName',
              '/s/$longName/SKILL.md',
              SkillSource.global),
          throwsA(isA<SkillParseError>()));
    });

    test('throws on description exceeding 1024 chars', () {
      final longDesc = 'a' * 1025;
      expect(
          () => parseSkillFrontmatter(
              '---\nname: x\ndescription: $longDesc\n---\n',
              '/s/x',
              '/s/x/SKILL.md',
              SkillSource.global),
          throwsA(isA<SkillParseError>()));
    });

    test('throws on unknown frontmatter fields', () {
      expect(
          () => parseSkillFrontmatter(
              '---\nname: x\ndescription: foo\nunknown: bar\n---\n',
              '/s/x',
              '/s/x/SKILL.md',
              SkillSource.global),
          throwsA(isA<SkillParseError>()));
    });

    test('single char name is valid', () {
      final meta = parseSkillFrontmatter('---\nname: x\ndescription: foo\n---\n',
          '/s/x', '/s/x/SKILL.md', SkillSource.global);
      expect(meta.name, 'x');
    });
  });
}
