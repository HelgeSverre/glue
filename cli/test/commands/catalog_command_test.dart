/// Unit tests for `glue catalog refresh`'s candidate-URL fallback. We bypass
/// the [Command] surface and exercise [refreshCatalog] directly so we can
/// inject a stub fetcher and a scratch cache path without depending on
/// `Platform.environment` or the real network.
library;

import 'dart:io';

import 'package:glue/src/commands/catalog_command.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:test/test.dart';

class _StubFetcher implements RemoteCatalogFetcher {
  _StubFetcher(this._fn);

  final Future<FetchResult> Function(Uri) _fn;

  @override
  Future<FetchResult> fetch(
    Uri uri, {
    String? ifModifiedSince,
    Duration timeout = const Duration(seconds: 10),
  }) => _fn(uri);
}

Directory _scratch() =>
    Directory.systemTemp.createTempSync('glue_catalog_cmd_test_');

/// A minimal body that survives `parseCatalogYaml` (H5 validates the fetched
/// body before writing it to the cache, so fixtures must be real catalogs).
const _validCatalog =
    'version: 1\n'
    'defaults:\n'
    '  model: anthropic/claude\n'
    'providers: {}\n';

void main() {
  group('refreshCatalog', () {
    test('writes cache from first successful candidate and stops', () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final cachePath = '${dir.path}/models.yaml';

      final attempted = <Uri>[];
      final outcome = await refreshCatalog(
        candidates: [
          Uri.parse('https://example.invalid/a.yaml'),
          Uri.parse('https://example.invalid/b.yaml'),
        ],
        cachePath: cachePath,
        fetcher: _StubFetcher((uri) async {
          attempted.add(uri);
          return const FetchUpdated(yaml: _validCatalog);
        }),
      );

      expect(outcome, isA<RefreshWrote>());
      expect(
        attempted,
        hasLength(1),
        reason: 'fallback should not run after success',
      );
      expect(File(cachePath).readAsStringSync(), contains('version'));
    });

    test('falls back to next candidate when primary fails', () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final cachePath = '${dir.path}/models.yaml';

      final attempted = <Uri>[];
      final outcome = await refreshCatalog(
        candidates: [
          Uri.parse('https://primary.invalid/m.yaml'),
          Uri.parse('https://fallback.invalid/m.yaml'),
        ],
        cachePath: cachePath,
        fetcher: _StubFetcher((uri) async {
          attempted.add(uri);
          if (uri.host == 'primary.invalid') {
            return const FetchFailed(reason: 'connection refused');
          }
          return const FetchUpdated(yaml: _validCatalog);
        }),
      );

      expect(outcome, isA<RefreshWrote>());
      expect(attempted.map((u) => u.host), [
        'primary.invalid',
        'fallback.invalid',
      ]);
      expect(File(cachePath).existsSync(), isTrue);
    });

    test(
      'returns RefreshAllFailed with each reason when nothing works',
      () async {
        final dir = _scratch();
        addTearDown(() => dir.deleteSync(recursive: true));
        final cachePath = '${dir.path}/models.yaml';

        final outcome = await refreshCatalog(
          candidates: [
            Uri.parse('https://a.invalid/m.yaml'),
            Uri.parse('https://b.invalid/m.yaml'),
          ],
          cachePath: cachePath,
          fetcher: _StubFetcher(
            (uri) async => FetchFailed(reason: 'dns: ${uri.host}'),
          ),
        );

        expect(outcome, isA<RefreshAllFailed>());
        final failures = (outcome as RefreshAllFailed).failures;
        expect(failures, hasLength(2));
        expect(failures[0].reason, 'dns: a.invalid');
        expect(failures[1].reason, 'dns: b.invalid');
        expect(
          File(cachePath).existsSync(),
          isFalse,
          reason: 'cache must not be created on total failure',
        );
      },
    );

    test('rejects a fetched body that is not a valid catalog and does not '
        'overwrite an existing cache (H5)', () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final cachePath = '${dir.path}/models.yaml';
      // A previously-good cache the refresh must not clobber.
      File(cachePath).writeAsStringSync('version: 1\nproviders: {}\n');

      final outcome = await refreshCatalog(
        candidates: [Uri.parse('https://a.invalid/m.yaml')],
        cachePath: cachePath,
        fetcher: _StubFetcher(
          (_) async => const FetchUpdated(yaml: ': not : valid : yaml ['),
        ),
      );

      expect(
        outcome,
        isA<RefreshAllFailed>(),
        reason: 'invalid catalog must not count as a successful write',
      );
      expect(
        File(cachePath).readAsStringSync(),
        'version: 1\nproviders: {}\n',
        reason: 'the good cache must be preserved untouched',
      );
    });

    test(
      'falls back to the next candidate when a body fails validation (H5)',
      () async {
        final dir = _scratch();
        addTearDown(() => dir.deleteSync(recursive: true));
        final cachePath = '${dir.path}/models.yaml';

        final attempted = <Uri>[];
        final outcome = await refreshCatalog(
          candidates: [
            Uri.parse('https://primary.invalid/m.yaml'),
            Uri.parse('https://fallback.invalid/m.yaml'),
          ],
          cachePath: cachePath,
          fetcher: _StubFetcher((uri) async {
            attempted.add(uri);
            if (uri.host == 'primary.invalid') {
              return const FetchUpdated(yaml: 'garbage: [unterminated');
            }
            return const FetchUpdated(yaml: _validCatalog);
          }),
        );

        expect(outcome, isA<RefreshWrote>());
        expect(attempted.map((u) => u.host), [
          'primary.invalid',
          'fallback.invalid',
        ]);
        expect(File(cachePath).readAsStringSync(), contains('version'));
      },
    );

    test(
      'treats FetchNotModified as success without rewriting cache',
      () async {
        final dir = _scratch();
        addTearDown(() => dir.deleteSync(recursive: true));
        final cachePath = '${dir.path}/models.yaml';
        File(cachePath).writeAsStringSync('existing');

        final outcome = await refreshCatalog(
          candidates: [Uri.parse('https://a.invalid/m.yaml')],
          cachePath: cachePath,
          fetcher: _StubFetcher((_) async => const FetchNotModified()),
        );

        expect(outcome, isA<RefreshNotModified>());
        expect(File(cachePath).readAsStringSync(), 'existing');
      },
    );
  });

  group('defaultCatalogUrls', () {
    test('points at the canonical GitHub raw URL', () {
      expect(defaultCatalogUrls, hasLength(1));
      expect(defaultCatalogUrls.single, contains('raw.githubusercontent.com'));
      expect(
        defaultCatalogUrls.single,
        endsWith('/docs/reference/models.yaml'),
      );
    });
  });
}
