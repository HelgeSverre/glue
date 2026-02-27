import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:glue/src/input/file_expander.dart';

void main() {
  group('extractFileRefs', () {
    test('single @path token', () {
      expect(extractFileRefs('@foo.dart'), ['foo.dart']);
    });

    test('multiple tokens in one message', () {
      expect(
        extractFileRefs('@foo.dart and @bar.json'),
        ['foo.dart', 'bar.json'],
      );
    });

    test('no tokens returns empty list', () {
      expect(extractFileRefs('no file refs here'), isEmpty);
    });

    test('email addresses are not matched', () {
      expect(extractFileRefs('user@host.com'), isEmpty);
    });

    test('@token at start of input', () {
      expect(extractFileRefs('@start.dart rest'), ['start.dart']);
    });

    test('paths with subdirectories', () {
      expect(
        extractFileRefs('@lib/src/agent/core.dart'),
        ['lib/src/agent/core.dart'],
      );
    });

    test('double-quoted paths with spaces', () {
      expect(
        extractFileRefs('@"path with spaces/file.dart"'),
        ['path with spaces/file.dart'],
      );
    });

    test('single-quoted paths', () {
      expect(
        extractFileRefs("@'some/path.dart'"),
        ['some/path.dart'],
      );
    });
  });

  group('expandFileRefs', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('file_expander_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('single file expansion', () {
      final file = File(p.join(tmpDir.path, 'hello.dart'));
      file.writeAsStringSync('void main() {}');

      final result = expandFileRefs('@hello.dart', cwd: tmpDir.path);
      expect(result, contains('[hello.dart]'));
      expect(result, contains('```dart'));
      expect(result, contains('void main() {}'));
    });

    test('multiple file expansion', () {
      File(p.join(tmpDir.path, 'a.dart')).writeAsStringSync('aaa');
      File(p.join(tmpDir.path, 'b.json')).writeAsStringSync('bbb');

      final result = expandFileRefs('@a.dart @b.json', cwd: tmpDir.path);
      expect(result, contains('[a.dart]'));
      expect(result, contains('```dart'));
      expect(result, contains('aaa'));
      expect(result, contains('[b.json]'));
      expect(result, contains('```json'));
      expect(result, contains('bbb'));
    });

    test('missing file appends [not found]', () {
      final result = expandFileRefs('@missing.dart', cwd: tmpDir.path);
      expect(result, contains('@missing.dart [not found]'));
    });

    test('no refs returns input unchanged', () {
      const input = 'just some text';
      expect(expandFileRefs(input, cwd: tmpDir.path), input);
    });

    test('extension maps to language tag', () {
      for (final entry in {
        'test.dart': 'dart',
        'test.json': 'json',
        'test.yaml': 'yaml',
        'test.md': 'markdown',
        'test.sh': 'sh',
        'test.ts': 'typescript',
        'test.js': 'javascript',
        'test.py': 'python',
        'test.html': 'html',
        'test.css': 'css',
        'test.sql': 'sql',
        'test.rs': 'rust',
        'test.go': 'go',
      }.entries) {
        File(p.join(tmpDir.path, entry.key)).writeAsStringSync('x');
        final result = expandFileRefs('@${entry.key}', cwd: tmpDir.path);
        expect(result, contains('```${entry.value}'),
            reason: '${entry.key} should map to ${entry.value}');
      }
    });

    test('unknown extension produces no language tag', () {
      File(p.join(tmpDir.path, 'data.xyz')).writeAsStringSync('x');
      final result = expandFileRefs('@data.xyz', cwd: tmpDir.path);
      expect(result, contains('```\n'));
    });

    test('file > 100KB appends [too large]', () {
      final file = File(p.join(tmpDir.path, 'big.dart'));
      file.writeAsStringSync('x' * (101 * 1024));

      final result = expandFileRefs('@big.dart', cwd: tmpDir.path);
      expect(result, contains('@big.dart [too large:'));
      expect(result, contains('KB]'));
    });

    test('email not expanded', () {
      const input = 'contact user@host.com please';
      expect(expandFileRefs(input, cwd: tmpDir.path), input);
    });

    test('file in subdirectory', () {
      final sub = Directory(p.join(tmpDir.path, 'sub'));
      sub.createSync();
      File(p.join(sub.path, 'nested.dart')).writeAsStringSync('nested');

      final result = expandFileRefs('@sub/nested.dart', cwd: tmpDir.path);
      expect(result, contains('[sub/nested.dart]'));
      expect(result, contains('nested'));
    });

    test('file containing triple backticks uses dynamic fence', () {
      final file = File(p.join(tmpDir.path, 'tricky.md'));
      file.writeAsStringSync('some\n```\ncode\n```\n');

      final result = expandFileRefs('@tricky.md', cwd: tmpDir.path);
      expect(result, contains('````'));
    });

    test('quoted path with spaces', () {
      final sub = Directory(p.join(tmpDir.path, 'my dir'));
      sub.createSync();
      File(p.join(sub.path, 'file.dart')).writeAsStringSync('spaced');

      final result = expandFileRefs('@"my dir/file.dart"', cwd: tmpDir.path);
      expect(result, contains('[my dir/file.dart]'));
      expect(result, contains('spaced'));
    });
  });
}
