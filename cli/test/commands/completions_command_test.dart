import 'dart:io';

import 'package:glue/glue.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory home;

  setUp(() {
    home = Directory.systemTemp.createTempSync('glue_completions_');
  });

  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  group('resolveZshCompletionsDir', () {
    test('falls back to ~/.zsh/completions when no candidate exists', () {
      expect(
        resolveZshCompletionsDir(home.path).path,
        p.join(home.path, '.zsh', 'completions'),
      );
    });

    test('prefers an existing candidate over the default', () {
      Directory(p.join(home.path, '.zfunc')).createSync();

      expect(
        resolveZshCompletionsDir(home.path).path,
        p.join(home.path, '.zfunc'),
      );
    });

    test('prefers ~/.zsh/completions when several candidates exist', () {
      Directory(p.join(home.path, '.zfunc')).createSync();
      Directory(
        p.join(home.path, '.zsh', 'completions'),
      ).createSync(recursive: true);

      expect(
        resolveZshCompletionsDir(home.path).path,
        p.join(home.path, '.zsh', 'completions'),
      );
    });
  });

  group('zshCompletionScript', () {
    test('tags the function for autoload on the first line', () {
      expect(zshCompletionScript('glue').split('\n').first, '#compdef glue');
    });

    test('delegates to the shared `completion --` backend', () {
      expect(zshCompletionScript('glue'), contains('glue completion -- '));
    });

    test('does not set global completion zstyles', () {
      expect(zshCompletionScript('glue'), isNot(contains("':completion:*'")));
    });
  });
}
