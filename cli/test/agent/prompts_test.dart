import 'dart:io';
import 'package:test/test.dart';
import 'package:glue/glue.dart';

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
}
