/// Read-only client for Ollama's metadata endpoints.
///
/// Today we only need `/api/tags` — the list of locally-pulled models —
/// so the model picker can stop lying about which catalog entries are
/// actually runnable. The client is fail-soft by construction: every
/// network error, timeout, non-200, or malformed JSON collapses to an
/// empty list. Callers never need to try/catch.
///
/// A tiny in-memory cache (30 s TTL keyed by base URL) absorbs the case
/// where a user opens the picker repeatedly within a short window.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// One entry from `GET /api/tags` — the fields we actually use.
class OllamaInstalledModel {
  const OllamaInstalledModel({
    required this.tag,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  /// Fully-qualified tag as Ollama reports it, e.g. `qwen3-coder:30b`.
  final String tag;
  final int sizeBytes;
  final DateTime? modifiedAt;
}

/// One NDJSON frame from `POST /api/pull`. Ollama emits a `status` string
/// (`pulling manifest`, `downloading`, `success`, …) and, for download
/// frames, `total`/`completed` byte counters.
class OllamaPullProgress {
  const OllamaPullProgress({
    required this.status,
    this.total,
    this.completed,
    this.digest,
    this.error,
  });

  final String status;
  final int? total;
  final int? completed;
  final String? digest;
  final String? error;

  bool get isSuccess => status.toLowerCase() == 'success';
  bool get hasError => error != null && error!.isNotEmpty;

  /// `0.0`..`1.0` when download byte counters are present, else null.
  double? get fraction {
    if (total == null || total == 0 || completed == null) return null;
    return (completed! / total!).clamp(0.0, 1.0);
  }
}

class OllamaDiscovery {
  OllamaDiscovery({
    required this.baseUrl,
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 2),
    this.cacheTtl = const Duration(seconds: 30),
    DateTime Function()? now,
  })  : _clientFactory = clientFactory ?? http.Client.new,
        _now = now ?? DateTime.now;

  /// Ollama's HTTP root. Accepts the `/v1` suffix (OpenAI-compat path) and
  /// the bare form — we normalise internally so callers don't have to.
  final Uri baseUrl;
  final Duration timeout;
  final Duration cacheTtl;
  final http.Client Function() _clientFactory;
  final DateTime Function() _now;

  static final _cache = <String, _CacheEntry>{};

  /// `GET /api/tags`. Returns an empty list on any failure — never throws.
  Future<List<OllamaInstalledModel>> listInstalled() async {
    final key = _cacheKey();
    final cached = _cache[key];
    if (cached != null && _now().isBefore(cached.expiresAt)) {
      return cached.models;
    }

    final models = await _fetch();
    _cache[key] = _CacheEntry(
      models: models,
      expiresAt: _now().add(cacheTtl),
    );
    return models;
  }

  /// Drop the cache entry for this base URL. Tests and `/model refresh`
  /// call this; normal picker open should rely on the TTL.
  void invalidateCache() {
    _cache.remove(_cacheKey());
  }

  /// Probe whether the daemon is reachable. 200 ⇒ true; anything else
  /// (refused, timeout, malformed response) ⇒ false. Never throws. Bypasses
  /// the [listInstalled] cache because "is the daemon up *right now*?" is a
  /// question the cache shouldn't answer.
  Future<bool> ping() async {
    final client = _clientFactory();
    try {
      final response = await client.get(_tagsUri()).timeout(timeout);
      return response.statusCode == 200;
    } on TimeoutException {
      return false;
    } on SocketException {
      return false;
    } on http.ClientException {
      return false;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// Stream NDJSON progress from `POST /api/pull`. The stream completes
  /// when Ollama finishes (a `{"status":"success"}` frame) or errors out.
  /// On error the final frame carries [OllamaPullProgress.error] so callers
  /// can surface it without try/catch boilerplate.
  Stream<OllamaPullProgress> pullModel(String tag) async* {
    final client = _clientFactory();
    try {
      final request = http.Request('POST', _pullUri());
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({'model': tag, 'stream': true});
      final response = await client.send(request);
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        yield OllamaPullProgress(
          status: 'error',
          error: 'ollama /api/pull HTTP ${response.statusCode}: $body',
        );
        return;
      }
      // NDJSON: one JSON object per line.
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final obj = jsonDecode(line);
          if (obj is! Map) continue;
          yield OllamaPullProgress(
            status: obj['status']?.toString() ?? '',
            total: (obj['total'] as num?)?.toInt(),
            completed: (obj['completed'] as num?)?.toInt(),
            digest: obj['digest']?.toString(),
            error: obj['error']?.toString(),
          );
        } catch (_) {
          // Malformed line — skip it. Ollama occasionally emits trailing
          // whitespace or partial fragments we don't need.
        }
      }
    } catch (e) {
      yield OllamaPullProgress(status: 'error', error: e.toString());
    } finally {
      client.close();
    }
  }

  Uri _pullUri() {
    final path = baseUrl.path;
    final stripped = path.endsWith('/v1')
        ? path.substring(0, path.length - 3)
        : path.endsWith('/v1/')
            ? path.substring(0, path.length - 4)
            : path;
    return baseUrl.replace(
      path: '${stripped.endsWith('/') ? stripped : "$stripped/"}api/pull',
    );
  }

  /// For tests: wipe all cached entries regardless of base URL.
  static void resetCacheForTesting() => _cache.clear();

  Future<List<OllamaInstalledModel>> _fetch() async {
    final client = _clientFactory();
    try {
      final response = await client.get(_tagsUri()).timeout(timeout);
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];
      final models = decoded['models'];
      if (models is! List) return const [];
      final out = <OllamaInstalledModel>[];
      for (final raw in models) {
        if (raw is! Map) continue;
        final tag = raw['name'];
        if (tag is! String || tag.isEmpty) continue;
        out.add(
          OllamaInstalledModel(
            tag: tag,
            sizeBytes: (raw['size'] as num?)?.toInt() ?? 0,
            modifiedAt: _parseDate(raw['modified_at']),
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    } finally {
      client.close();
    }
  }

  Uri _tagsUri() {
    // Strip a trailing `/v1` (the OpenAI-compat path) so we always hit the
    // native `/api/tags` endpoint. `resolve` alone would keep the `/v1`
    // prefix in the final URL.
    final path = baseUrl.path;
    final stripped = path.endsWith('/v1')
        ? path.substring(0, path.length - 3)
        : path.endsWith('/v1/')
            ? path.substring(0, path.length - 4)
            : path;
    return baseUrl.replace(
      path: '${stripped.endsWith('/') ? stripped : "$stripped/"}api/tags',
    );
  }

  String _cacheKey() => baseUrl.toString();

  DateTime? _parseDate(dynamic raw) {
    if (raw is! String) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }
}

class _CacheEntry {
  _CacheEntry({required this.models, required this.expiresAt});

  final List<OllamaInstalledModel> models;
  final DateTime expiresAt;
}
