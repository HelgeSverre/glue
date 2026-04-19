/// Orchestrates catalog refreshes. Designed so startup never blocks on the
/// network:
///   - [refresh] is awaitable but swallows every failure.
///   - [scheduleNonBlocking] fires-and-forgets and returns a Future the
///     caller can await for tests, but production code typically discards it.
library;

import 'dart:io';

import 'package:glue/src/catalog/remote_catalog_fetcher.dart';

class CatalogRefreshService {
  CatalogRefreshService({required this.cachePath, required this.fetcher});

  final String cachePath;
  final RemoteCatalogFetcher fetcher;

  /// Fetch [url] and overwrite the local cache on [FetchUpdated]. All other
  /// outcomes (304, timeout, network error) leave the cache alone.
  ///
  /// The write is atomic (tmp + rename) so a crash mid-write cannot leave a
  /// truncated cache that would break next startup.
  Future<void> refresh(Uri url, {String? ifModifiedSince}) async {
    final result = await fetcher.fetch(url, ifModifiedSince: ifModifiedSince);
    switch (result) {
      case FetchUpdated(:final yaml):
        final file = File(cachePath);
        file.parent.createSync(recursive: true);
        final tmp = File('$cachePath.tmp');
        tmp.writeAsStringSync(yaml);
        tmp.renameSync(file.path);
      case FetchNotModified():
      case FetchFailed():
        // No-op — keep the existing cache. Logging is the caller's concern.
        break;
    }
  }

  /// Kicks off the refresh on the next microtask and returns immediately.
  Future<void> scheduleNonBlocking(Uri url, {String? ifModifiedSince}) {
    return Future<void>.microtask(
      () => refresh(url, ifModifiedSince: ifModifiedSince),
    );
  }
}
