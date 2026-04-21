/// Guarantees that catalog refresh never blocks startup and always falls back
/// to bundled + cached contents when remote fetching fails.
library;

import 'dart:async';
import 'dart:io';

import 'package:glue/src/catalog/catalog_refresh_service.dart';
import 'package:glue/src/catalog/remote_catalog_fetcher.dart';
import 'package:test/test.dart';

class _StubFetcher implements RemoteCatalogFetcher {
  _StubFetcher(this._fn);

  final Future<FetchResult> Function(Uri) _fn;

  @override
  Future<FetchResult> fetch(
    Uri uri, {
    String? ifModifiedSince,
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _fn(uri);
}

Directory _scratch() =>
    Directory.systemTemp.createTempSync('glue_refresh_test_');

void main() {
  group('CatalogRefreshService', () {
    test('refresh writes sanitized YAML to the cache path on success',
        () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final cachePath = '${dir.path}/models.yaml';

      final service = CatalogRefreshService(
        cachePath: cachePath,
        fetcher: _StubFetcher((uri) async => const FetchUpdated(
              yaml: '{"version":1,"providers":{}}',
            )),
      );

      await service.refresh(Uri.parse('https://example.com/c.yaml'));
      expect(File(cachePath).existsSync(), isTrue);
      expect(File(cachePath).readAsStringSync(), contains('version'));
    });

    test('refresh does not throw or rewrite the cache on FetchFailed',
        () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final cachePath = '${dir.path}/models.yaml';
      File(cachePath).writeAsStringSync('pre-existing-cache');

      final service = CatalogRefreshService(
        cachePath: cachePath,
        fetcher: _StubFetcher(
          (uri) async => const FetchFailed(reason: 'network unreachable'),
        ),
      );

      await service.refresh(Uri.parse('https://example.com/c.yaml'));
      expect(File(cachePath).readAsStringSync(), 'pre-existing-cache');
    });

    test('refresh leaves cache unchanged on FetchNotModified', () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final cachePath = '${dir.path}/models.yaml';
      File(cachePath).writeAsStringSync('valid-cache');

      final service = CatalogRefreshService(
        cachePath: cachePath,
        fetcher: _StubFetcher((uri) async => const FetchNotModified()),
      );

      await service.refresh(Uri.parse('https://example.com/c.yaml'));
      expect(File(cachePath).readAsStringSync(), 'valid-cache');
    });

    test('scheduleNonBlocking returns immediately and runs the fetch async',
        () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final cachePath = '${dir.path}/models.yaml';

      final completer = Completer<void>();
      final service = CatalogRefreshService(
        cachePath: cachePath,
        fetcher: _StubFetcher((uri) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          completer.complete();
          return const FetchUpdated(yaml: '{"version":1,"providers":{}}');
        }),
      );

      final stopwatch = Stopwatch()..start();
      final pending = service.scheduleNonBlocking(
        Uri.parse('https://example.com/c.yaml'),
      );
      stopwatch.stop();

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(20),
        reason: 'scheduleNonBlocking must not await the fetch',
      );
      await pending;
      expect(completer.isCompleted, isTrue);
    });
  });
}
