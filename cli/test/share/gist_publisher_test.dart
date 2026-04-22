import 'dart:io';

import 'package:glue/src/share/gist_publisher.dart';
import 'package:test/test.dart';

void main() {
  group('SessionGistPublisher', () {
    late Directory tempDir;
    late String markdownPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('gist_publisher_test_');
      markdownPath = '${tempDir.path}/session.md';
      File(markdownPath).writeAsStringSync('# Glue Session');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('publishes a gist after auth succeeds', () async {
      final calls = <List<String>>[];
      final publisher = SessionGistPublisher(
        runner: (executable, arguments) async {
          calls.add([executable, ...arguments]);
          if (arguments.first == 'auth') {
            return ProcessResult(1, 0, 'ok', '');
          }
          return ProcessResult(
            1,
            0,
            'https://gist.github.com/example/session',
            '',
          );
        },
      );

      final result = await publisher.publish(
        filePath: markdownPath,
        description: 'Glue session: Example',
      );

      expect(result.filePath, markdownPath);
      expect(result.url, 'https://gist.github.com/example/session');
      expect(calls, [
        ['gh', 'auth', 'status'],
        [
          'gh',
          'gist',
          'create',
          markdownPath,
          '--desc',
          'Glue session: Example'
        ],
      ]);
    });

    test('fails with a clear message when gh is unavailable', () async {
      final publisher = SessionGistPublisher(
        runner: (_, __) async {
          throw const ProcessException('gh', []);
        },
      );

      await expectLater(
        () => publisher.publish(
          filePath: markdownPath,
          description: 'Glue session: Example',
        ),
        throwsA(
          isA<GistPublishError>().having(
            (e) => e.message,
            'message',
            contains('GitHub CLI (`gh`) is not installed'),
          ),
        ),
      );
    });

    test('fails with auth guidance when gh auth status is non-zero', () async {
      final publisher = SessionGistPublisher(
        runner: (_, arguments) async {
          if (arguments.first == 'auth') {
            return ProcessResult(1, 1, '', 'not logged in');
          }
          return ProcessResult(1, 0, '', '');
        },
      );

      await expectLater(
        () => publisher.publish(
          filePath: markdownPath,
          description: 'Glue session: Example',
        ),
        throwsA(
          isA<GistPublishError>().having(
            (e) => e.message,
            'message',
            allOf(contains('gh auth login'), contains('not logged in')),
          ),
        ),
      );
    });

    test('fails when gist creation returns a non-zero exit code', () async {
      final publisher = SessionGistPublisher(
        runner: (_, arguments) async {
          if (arguments.first == 'auth') {
            return ProcessResult(1, 0, '', '');
          }
          return ProcessResult(1, 1, '', 'creation failed');
        },
      );

      await expectLater(
        () => publisher.publish(
          filePath: markdownPath,
          description: 'Glue session: Example',
        ),
        throwsA(
          isA<GistPublishError>().having(
            (e) => e.message,
            'message',
            allOf(contains('failed to create a gist'),
                contains('creation failed')),
          ),
        ),
      );
    });
  });
}
