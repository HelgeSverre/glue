import 'dart:io';

import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

void main() {
  group('expandUserPath', () {
    test('expands "~" alone to the home directory', () {
      expect(expandUserPath('~', home: '/home/me'), '/home/me');
    });

    test('expands a leading "~/" to the home directory', () {
      expect(expandUserPath('~/code/3d', home: '/home/me'), '/home/me/code/3d');
    });

    test('expands a leading "~\\" (Windows) to the home directory', () {
      expect(
        expandUserPath(r'~\proj', home: r'C:\Users\me'),
        r'C:\Users\me\proj',
      );
    });

    test('leaves absolute paths unchanged', () {
      expect(expandUserPath('/etc/hosts', home: '/home/me'), '/etc/hosts');
    });

    test('leaves relative paths unchanged', () {
      expect(expandUserPath('code/3d', home: '/home/me'), 'code/3d');
    });

    test('does not expand "~user" (only ~ and ~/ prefixes)', () {
      expect(expandUserPath('~bob/x', home: '/home/me'), '~bob/x');
    });

    test('does not expand a mid-path tilde', () {
      expect(expandUserPath('/a/~/b', home: '/home/me'), '/a/~/b');
    });

    test('returns the path unchanged when home is empty', () {
      expect(expandUserPath('~/x', home: ''), '~/x');
    });

    test('falls back to \$HOME from the environment when no home is given', () {
      final home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      // Only meaningful when a home is actually set in the environment.
      if (home != null && home.isNotEmpty) {
        expect(expandUserPath('~/x'), '$home/x');
      }
    });
  });
}
