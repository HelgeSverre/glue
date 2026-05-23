import 'dart:io';

import 'package:glue/glue.dart';
import 'package:test/test.dart';

SkillMeta _skill({
  required String name,
  required String description,
  required String path,
}) {
  return SkillMeta(
    name: name,
    description: description,
    skillDir: path.replaceAll('/SKILL.md', ''),
    skillMdPath: path,
    source: SkillSource.global,
  );
}

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('prompts_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  test('build includes AGENTS.md when present', () {
    File('${tmpDir.path}/AGENTS.md').writeAsStringSync('Run dart test');
    final prompt = Prompts.build(cwd: tmpDir.path);
    expect(prompt, contains('Run dart test'));
    expect(prompt, contains('AGENTS.md'));
  });

  test('build includes CLAUDE.md when present', () {
    File('${tmpDir.path}/CLAUDE.md').writeAsStringSync('Use package:test');
    final prompt = Prompts.build(cwd: tmpDir.path);
    expect(prompt, contains('Use package:test'));
    expect(prompt, contains('CLAUDE.md'));
  });

  test('build includes both when both present', () {
    File('${tmpDir.path}/AGENTS.md').writeAsStringSync('agents instructions');
    File('${tmpDir.path}/CLAUDE.md').writeAsStringSync('claude instructions');
    final prompt = Prompts.build(cwd: tmpDir.path);
    expect(prompt, contains('agents instructions'));
    expect(prompt, contains('claude instructions'));
  });

  test('build works without any files', () {
    final prompt = Prompts.build(cwd: tmpDir.path);
    expect(prompt, contains('Glue'));
    expect(prompt, isNot(contains('AGENTS.md')));
    expect(prompt, isNot(contains('<available_skills>')));
  });

  test('build still accepts projectContext', () {
    final prompt = Prompts.build(cwd: tmpDir.path, projectContext: 'custom');
    expect(prompt, contains('custom'));
  });

  test('truncates files over 50KB', () {
    File('${tmpDir.path}/AGENTS.md').writeAsStringSync('x' * 60000);
    final prompt = Prompts.build(cwd: tmpDir.path);
    expect(prompt, contains('truncated'));
  });

  test('walks up to .git root and loads ancestor AGENTS.md', () {
    Directory('${tmpDir.path}/.git').createSync();
    File('${tmpDir.path}/AGENTS.md').writeAsStringSync('root rules');
    final pkg = Directory('${tmpDir.path}/packages/foo')
      ..createSync(recursive: true);
    File('${pkg.path}/AGENTS.md').writeAsStringSync('package rules');

    final prompt = Prompts.build(cwd: pkg.path);

    expect(prompt, contains('root rules'));
    expect(prompt, contains('package rules'));
    expect(prompt, contains('## Project Instructions (AGENTS.md)'));
    expect(
      prompt,
      contains('## Project Instructions (packages/foo/AGENTS.md)'),
    );
    // Closer file wins by appearing later.
    expect(
      prompt.indexOf('root rules'),
      lessThan(prompt.indexOf('package rules')),
    );
  });

  test('stops at .git boundary — does not read outside the workspace', () {
    final outside = Directory('${tmpDir.path}/outside')..createSync();
    File('${outside.path}/AGENTS.md').writeAsStringSync('OUTSIDE');
    final inside = Directory('${outside.path}/repo')..createSync();
    Directory('${inside.path}/.git').createSync();
    File('${inside.path}/AGENTS.md').writeAsStringSync('INSIDE');

    final prompt = Prompts.build(cwd: inside.path);

    expect(prompt, contains('INSIDE'));
    expect(prompt, isNot(contains('OUTSIDE')));
  });

  test('stops at home directory boundary', () {
    // Simulate cwd = $HOME/proj with no .git anywhere. Walk should not escape
    // above the home boundary, but with no .git found, we collapse to cwd-only
    // discovery, so an AGENTS.md above $HOME must not appear.
    final home = Directory('${tmpDir.path}/home')..createSync();
    File('${tmpDir.path}/AGENTS.md').writeAsStringSync('ABOVE HOME');
    final proj = Directory('${home.path}/proj')..createSync();
    File('${proj.path}/AGENTS.md').writeAsStringSync('IN PROJ');

    final prompt = Prompts.build(cwd: proj.path, homeDir: home.path);

    expect(prompt, contains('IN PROJ'));
    expect(prompt, isNot(contains('ABOVE HOME')));
  });

  test('without .git anywhere, falls back to cwd-only discovery', () {
    final parent = Directory('${tmpDir.path}/parent')..createSync();
    File('${parent.path}/AGENTS.md').writeAsStringSync('PARENT');
    final child = Directory('${parent.path}/child')..createSync();
    File('${child.path}/AGENTS.md').writeAsStringSync('CHILD');

    // Use homeDir to bound the walk so this test does not depend on the
    // host filesystem layout above tmpDir.
    final prompt = Prompts.build(cwd: child.path, homeDir: tmpDir.path);

    expect(prompt, contains('CHILD'));
    expect(prompt, isNot(contains('PARENT')));
  });

  test('build renders available_skills XML when skills are provided', () {
    final prompt = Prompts.build(
      cwd: tmpDir.path,
      skills: [
        _skill(
          name: 'code-review',
          description: 'Review code changes',
          path: '/tmp/skills/code-review/SKILL.md',
        ),
      ],
    );
    expect(prompt, contains('## Skills'));
    expect(prompt, contains('<available_skills>'));
    expect(prompt, contains('<name>code-review</name>'));
    expect(prompt, contains('<description>Review code changes</description>'));
    expect(
      prompt,
      contains('<location>/tmp/skills/code-review/SKILL.md</location>'),
    );
  });

  test('build escapes XML in skill metadata fields', () {
    final prompt = Prompts.build(
      cwd: tmpDir.path,
      skills: [
        _skill(
          name: 'xml-safe',
          description: 'Use <tag> & keep > 0',
          path: '/tmp/a&b/<skills>/xml-safe/SKILL.md',
        ),
      ],
    );
    expect(prompt, contains('Use &lt;tag&gt; &amp; keep &gt; 0'));
    expect(prompt, contains('/tmp/a&amp;b/&lt;skills&gt;/xml-safe/SKILL.md'));
  });

  test('build includes explicit skill trigger instructions', () {
    final prompt = Prompts.build(
      cwd: tmpDir.path,
      skills: [
        _skill(
          name: 'code-review',
          description: 'Review code changes',
          path: '/tmp/skills/code-review/SKILL.md',
        ),
      ],
    );
    expect(prompt, contains('Skill trigger rules:'));
    expect(prompt, contains('If the user explicitly names a skill'));
    expect(prompt, contains('If the task clearly matches a skill description'));
    expect(prompt, contains('If a named skill is unavailable'));
    expect(prompt, contains('After loading a skill, follow its SKILL.md'));
  });
}
