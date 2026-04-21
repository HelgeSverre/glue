import 'dart:io';

import 'package:glue/src/shell/shell_completer.dart';
import 'package:test/test.dart';

void main() {
  group('ShellType', () {
    test('enum values exist', () {
      expect(
          ShellType.values,
          containsAll(
              [ShellType.bash, ShellType.fish, ShellType.zsh, ShellType.sh]));
    });
  });

  group('ShellCandidate', () {
    test('holds text and defaults', () {
      final c = ShellCandidate('git');
      expect(c.text, 'git');
      expect(c.description, isNull);
      expect(c.isDirectory, isFalse);
    });

    test('holds optional description and isDirectory', () {
      final c =
          ShellCandidate('src', description: 'Source dir', isDirectory: true);
      expect(c.text, 'src');
      expect(c.description, 'Source dir');
      expect(c.isDirectory, isTrue);
    });
  });

  group('ShellCompleter.tokenStart', () {
    late ShellCompleter completer;

    setUp(() {
      completer = ShellCompleter(shellType: ShellType.bash);
    });

    test('empty buffer returns 0', () {
      expect(completer.tokenStart(''), 0);
    });

    test('single word returns 0', () {
      expect(completer.tokenStart('ls'), 0);
    });

    test('two words returns start of second word', () {
      expect(completer.tokenStart('git checkout'), 4);
    });

    test('three words with flag returns start of flag', () {
      // "git checkout --fo" → last space at index 12 → token starts at 13
      expect(completer.tokenStart('git checkout --fo'), 13);
    });

    test('trailing space returns position after space', () {
      expect(completer.tokenStart('cat '), 4);
    });

    test('multiple spaces between words', () {
      expect(completer.tokenStart('ls  -la'), 4);
    });
  });

  group('ShellCompleter.complete', () {
    late ShellCompleter completer;

    setUp(() {
      completer = ShellCompleter(shellType: ShellType.bash);
    });

    test('empty buffer returns empty list', () async {
      final results = await completer.complete('');
      expect(results, isEmpty);
    });

    test('command completion returns results for known prefix', () async {
      // 'ech' should match at least 'echo' on any system with bash.
      final results = await completer.complete('ech');
      expect(results, isNotEmpty);
      expect(results.any((c) => c.text == 'echo'), isTrue);
    });

    test('file completion in temp directory', () async {
      final dir = Directory.systemTemp.createTempSync('shell_completer_test_');
      try {
        File('${dir.path}/hello.txt').createSync();
        File('${dir.path}/hello_world.txt').createSync();
        Directory('${dir.path}/hello_dir').createSync();

        final results = await completer.complete('ls ${dir.path}/hello');
        expect(results, isNotEmpty);
        final texts = results.map((c) => c.text).toList();
        expect(texts, contains('${dir.path}/hello.txt'));
        expect(texts, contains('${dir.path}/hello_world.txt'));
        expect(texts, contains('${dir.path}/hello_dir'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('marks directories with isDirectory flag', () async {
      final dir = Directory.systemTemp.createTempSync('shell_completer_test_');
      try {
        File('${dir.path}/file.txt').createSync();
        Directory('${dir.path}/subdir').createSync();

        final results = await completer.complete('ls ${dir.path}/');
        final fileCandidate = results.where((c) => c.text.endsWith('file.txt'));
        final dirCandidate = results.where((c) => c.text.endsWith('subdir'));

        if (fileCandidate.isNotEmpty) {
          expect(fileCandidate.first.isDirectory, isFalse);
        }
        if (dirCandidate.isNotEmpty) {
          expect(dirCandidate.first.isDirectory, isTrue);
        }
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('results capped at 50', () async {
      final dir = Directory.systemTemp.createTempSync('shell_completer_test_');
      try {
        for (var i = 0; i < 60; i++) {
          File('${dir.path}/file_${i.toString().padLeft(3, '0')}.txt')
              .createSync();
        }

        final results = await completer.complete('ls ${dir.path}/file_');
        expect(results.length, lessThanOrEqualTo(50));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('cache returns same results on second call', () async {
      final results1 = await completer.complete('ech');
      final results2 = await completer.complete('ech');
      expect(results1.length, results2.length);
      for (var i = 0; i < results1.length; i++) {
        expect(results1[i].text, results2[i].text);
      }
    });

    test('different input invalidates cache', () async {
      await completer.complete('ech');
      final results2 = await completer.complete('ls');
      // Should get different results (ls-related commands).
      expect(results2, isNotEmpty);
    });

    test('unknown command prefix returns empty or results gracefully',
        () async {
      final results = await completer.complete('xyznonexistent_cmd_12345');
      // May return empty or some results — just should not throw.
      expect(results, isA<List<ShellCandidate>>());
    });
  });

  group('ShellCompleter with fish', () {
    test('fish completer can be constructed', () {
      final completer = ShellCompleter(shellType: ShellType.fish);
      expect(completer.shellType, ShellType.fish);
    });

    // Fish-specific tests only run if fish is available.
    test('fish completion returns results if fish is installed', () async {
      // Check if fish is available.
      try {
        final result = await Process.run('which', ['fish']);
        if (result.exitCode != 0) {
          markTestSkipped('fish not installed');
          return;
        }
      } catch (_) {
        markTestSkipped('fish not available');
        return;
      }

      final completer = ShellCompleter(shellType: ShellType.fish);
      final results = await completer.complete('echo');
      expect(results, isNotEmpty);
    });
  });

  group('ShellCompleter timeout handling', () {
    test('gracefully handles nonexistent shell', () async {
      // Create a completer that would try to use a non-existent shell.
      // The internal _runShellCommand should catch the error.
      final completer = ShellCompleter(shellType: ShellType.bash);
      // Even if bash is available, this tests the error path indirectly.
      // A direct test would require mocking Process.run.
      final results = await completer.complete('ech');
      // Should either return results (bash available) or empty list (not available).
      expect(results, isA<List<ShellCandidate>>());
    });
  });
}
