import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:glue/src/ui/at_file_hint.dart';

void main() {
  late Directory tmpDir;
  late AtFileHint hint;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('at_file_hint_test_');
    // Create test file structure:
    //   main.dart, pubspec.yaml, README.md
    //   lib/app.dart, lib/utils.dart
    //   my dir/spaced.dart
    File(p.join(tmpDir.path, 'main.dart')).createSync();
    File(p.join(tmpDir.path, 'pubspec.yaml')).createSync();
    File(p.join(tmpDir.path, 'README.md')).createSync();
    Directory(p.join(tmpDir.path, 'lib')).createSync();
    File(p.join(tmpDir.path, 'lib', 'app.dart')).createSync();
    File(p.join(tmpDir.path, 'lib', 'utils.dart')).createSync();
    Directory(p.join(tmpDir.path, 'my dir')).createSync();
    File(p.join(tmpDir.path, 'my dir', 'spaced.dart')).createSync();
    Directory(p.join(tmpDir.path, 'lib', 'src')).createSync();
    File(p.join(tmpDir.path, 'lib', 'src', 'app.dart')).createSync();
    File(p.join(tmpDir.path, 'lib', 'src', 'config.dart')).createSync();
    Directory(p.join(tmpDir.path, 'lib', 'src', 'tools')).createSync();
    File(p.join(tmpDir.path, 'lib', 'src', 'tools', 'grep.dart')).createSync();

    hint = AtFileHint(cwd: tmpDir.path);
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  group('AtFileHint', () {
    test('starts inactive', () {
      expect(hint.active, isFalse);
      expect(hint.overlayHeight, 0);
      expect(hint.matchCount, 0);
    });

    test('activates on @ at start of input', () {
      hint.update('@', 1);
      expect(hint.active, isTrue);
      expect(hint.matchCount, greaterThan(0));
    });

    test('activates on space + @', () {
      hint.update('hello @', 7);
      expect(hint.active, isTrue);
      expect(hint.matchCount, greaterThan(0));
    });

    test('does NOT activate on user@ (email-like)', () {
      hint.update('user@', 5);
      expect(hint.active, isFalse);
    });

    test('filters by partial filename (fuzzy contains match)', () {
      hint.update('@main', 5);
      expect(hint.active, isTrue);
      // 'main.dart' contains 'main'
      expect(hint.matchCount, 1);
    });

    test('contains match finds substring anywhere', () {
      hint.update('@spec', 5);
      expect(hint.active, isTrue);
      // 'pubspec.yaml' contains 'spec'
      expect(hint.matchCount, 1);
    });

    test('filters by subdirectory prefix', () {
      hint.update('@lib/', 5);
      expect(hint.active, isTrue);
      // lib/ contains app.dart, src/, utils.dart
      expect(hint.matchCount, 3);
    });

    test('dismisses when no matches', () {
      hint.update('@zzzznonexistent', 16);
      expect(hint.active, isFalse);
    });

    test('moveDown wraps around', () {
      hint.update('@', 1);
      expect(hint.active, isTrue);
      final count = hint.matchCount;
      expect(hint.selected, 0);
      for (var i = 0; i < count; i++) {
        hint.moveDown();
      }
      expect(hint.selected, 0); // wrapped
    });

    test('moveUp wraps around', () {
      hint.update('@', 1);
      expect(hint.active, isTrue);
      final count = hint.matchCount;
      expect(hint.selected, 0);
      hint.moveUp();
      expect(hint.selected, count - 1);
    });

    test('accept returns @path', () {
      hint.update('@main', 5);
      expect(hint.active, isTrue);
      final result = hint.accept('@main', 5);
      expect(result?.text, '@main.dart');
      expect(result?.cursor, '@main.dart'.length);
      expect(hint.active, isFalse);
    });

    test('accept auto-quotes paths with spaces', () {
      hint.update('@my', 3);
      expect(hint.active, isTrue);
      // 'my dir/' should be a match (directory)
      final result = hint.accept('@my', 3);
      expect(result?.text, '@"my dir/"');
    });

    test('accept returns directory with trailing /', () {
      hint.update('@lib', 4);
      expect(hint.active, isTrue);
      // 'lib/' directory should match
      final result = hint.accept('@lib', 4);
      expect(result?.text, '@lib/');
    });

    test('dismiss clears state', () {
      hint.update('@', 1);
      expect(hint.active, isTrue);
      hint.moveDown();
      hint.dismiss();
      expect(hint.active, isFalse);
      expect(hint.selected, 0);
      expect(hint.matchCount, 0);
    });

    test('render returns correct line count', () {
      hint.update('@', 1);
      expect(hint.active, isTrue);
      final lines = hint.render(80);
      expect(lines.length, hint.matchCount);
    });

    test('overlayHeight capped at maxVisible', () {
      // We have: lib/, my dir/, main.dart, pubspec.yaml, README.md
      // That's 5 items which is under maxVisible=8, so check capping logic
      hint.update('@', 1);
      expect(hint.overlayHeight, hint.matchCount);
      expect(hint.overlayHeight, lessThanOrEqualTo(AtFileHint.maxVisible));
    });

    test('directories shown with trailing /', () {
      hint.update('@', 1);
      final lines = hint.render(80);
      // lib/ and my dir/ should appear with trailing /
      final joined = lines.join('\n');
      expect(joined, contains('lib/'));
    });

    test('directories sorted before files', () {
      hint.update('@', 1);
      final lines = hint.render(80);
      // First entries should be directories (lib/, my dir/)
      // They use 📁 icon
      expect(lines[0], contains('📁'));
      expect(lines[1], contains('📁'));
    });

    test('tokenStart tracks position of @ in buffer', () {
      hint.update('hello @main', 11);
      expect(hint.active, isTrue);
      expect(hint.tokenStart, 6);
    });

    test('tokenStart is 0 when @ at start', () {
      hint.update('@main', 5);
      expect(hint.active, isTrue);
      expect(hint.tokenStart, 0);
    });

    test('skips hidden files', () {
      File(p.join(tmpDir.path, '.hidden')).createSync();
      hint.update('@', 1);
      final lines = hint.render(80);
      final joined = lines.join('\n');
      expect(joined, isNot(contains('.hidden')));
    });

    test('accept for subdirectory file returns full relative path', () {
      hint.update('@lib/app', 8);
      expect(hint.active, isTrue);
      final result = hint.accept('@lib/app', 8);
      expect(result?.text, '@lib/app.dart');
    });

    test('tokenStart preserved after accept for mid-buffer @mention', () {
      const buffer = 'look in the file at @lib';
      const cursor = 24;
      hint.update(buffer, cursor);
      expect(hint.active, isTrue);
      expect(hint.tokenStart, 20);
      final result = hint.accept(buffer, cursor);
      expect(result, isNotNull);
      expect(result!.text, startsWith('look in the file at @lib/'));
      // cursor lands at end of the spliced token
      expect(result.cursor, result.text.length);
    });

    test('recursive fuzzy finds file in nested dir', () {
      hint.update('@config', 7);
      expect(hint.active, isTrue);
      expect(hint.matchCount, greaterThanOrEqualTo(1));
      final result = hint.accept('@config', 7);
      expect(result?.text, '@lib/src/config.dart');
    });

    test('recursive fuzzy finds file at depth 3', () {
      hint.update('@grep', 5);
      expect(hint.active, isTrue);
      final result = hint.accept('@grep', 5);
      expect(result?.text, '@lib/src/tools/grep.dart');
    });

    test('recursive fuzzy shows relative path in display', () {
      hint.update('@config', 7);
      expect(hint.active, isTrue);
      final lines = hint.render(80);
      final joined = lines.join('\n');
      expect(joined, contains('lib/src/config.dart'));
    });

    test('recursive fuzzy ranks exact match first', () {
      hint.update('@app', 4);
      expect(hint.active, isTrue);
      final result = hint.accept('@app', 4);
      expect(result?.text, '@lib/app.dart');
    });

    test('recursive fuzzy prefers shorter paths', () {
      hint.update('@app.dart', 9);
      expect(hint.active, isTrue);
      final result = hint.accept('@app.dart', 9);
      expect(result?.text, '@lib/app.dart');
    });

    test('recursive fuzzy skips hidden directories', () {
      Directory(p.join(tmpDir.path, '.git')).createSync();
      File(p.join(tmpDir.path, '.git', 'config')).createSync();
      hint.update('@config', 7);
      final lines = hint.render(80);
      final joined = lines.join('\n');
      expect(joined, isNot(contains('.git')));
    });

    test('recursive does not duplicate cwd-level files', () {
      hint.update('@main', 5);
      expect(hint.matchCount, 1);
    });

    test('slash after recursive still does dir browse', () {
      hint.update('@lib/', 5);
      expect(hint.active, isTrue);
      expect(hint.matchCount, 3);
    });
  });
}
