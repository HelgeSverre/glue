/// Fetches a remote catalog YAML and returns a sanitized payload, never
/// throwing.
///
/// Failure cases (timeout, network error, non-2xx, parse error upstream) are
/// returned as [FetchFailed] values so the caller can decide whether to log.
library;

import 'dart:async';

import 'package:glue/src/catalog/remote_catalog_sanitizer.dart';
import 'package:http/http.dart' as http;

sealed class FetchResult {
  const FetchResult();
}

class FetchUpdated extends FetchResult {
  const FetchUpdated({required this.yaml, this.etag, this.lastModified});

  /// Sanitized YAML payload (credentials stripped).
  final String yaml;
  final String? etag;
  final String? lastModified;
}

class FetchNotModified extends FetchResult {
  const FetchNotModified();
}

class FetchFailed extends FetchResult {
  const FetchFailed({required this.reason});
  final String reason;
}

class RemoteCatalogFetcher {
  RemoteCatalogFetcher({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  Future<FetchResult> fetch(
    Uri uri, {
    String? ifModifiedSince,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final request = http.Request('GET', uri);
      request.headers['Accept'] = 'application/yaml, text/yaml, text/plain';
      if (ifModifiedSince != null) {
        request.headers['If-Modified-Since'] = ifModifiedSince;
      }
      final response = await _client.send(request).timeout(timeout);

      if (response.statusCode == 304) {
        await response.stream.drain<void>();
        return const FetchNotModified();
      }
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        return FetchFailed(reason: 'HTTP ${response.statusCode}');
      }

      final body = await response.stream.bytesToString();
      return FetchUpdated(
        yaml: sanitizeRemoteCatalogYaml(body),
        etag: response.headers['etag'],
        lastModified: response.headers['last-modified'],
      );
    } on TimeoutException {
      return const FetchFailed(reason: 'timeout');
    } catch (e) {
      // Strip the URI's query string before surfacing it, in case a user
      // embedded a token there.
      final safeUri = uri.replace(query: '').toString();
      return FetchFailed(reason: '${e.runtimeType} at $safeUri');
    }
  }
}
