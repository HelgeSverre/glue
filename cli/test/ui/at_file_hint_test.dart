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
      // lib/ contains app.dart and utils.dart
      expect(hint.matchCount, 2);
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
      final result = hint.accept();
      expect(result, '@main.dart');
      expect(hint.active, isFalse);
    });

    test('accept auto-quotes paths with spaces', () {
      hint.update('@my', 3);
      expect(hint.active, isTrue);
      // 'my dir/' should be a match (directory)
      final result = hint.accept();
      expect(result, '@"my dir/"');
    });

    test('accept returns directory with trailing /', () {
      hint.update('@lib', 4);
      expect(hint.active, isTrue);
      // 'lib/' directory should match
      final result = hint.accept();
      expect(result, '@lib/');
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
      final result = hint.accept();
      expect(result, '@lib/app.dart');
    });
  });
}
