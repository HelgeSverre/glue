import 'dart:async';
import 'package:http/http.dart' as http;

import 'package:glue_strategies/src/web/ssrf_guard.dart';

class JinaReaderClient {
  final String baseUrl;
  final String? apiKey;
  final int timeoutSeconds;
  final http.Client _client;
  final SsrfGuard _guard;

  JinaReaderClient({
    this.baseUrl = 'https://r.jina.ai',
    this.apiKey,
    this.timeoutSeconds = 30,
    http.Client? client,
    SsrfGuard? guard,
  }) : _client = client ?? http.Client(),
       _guard = guard ?? SsrfGuard();

  Uri buildReaderUrl(String targetUrl) => Uri.parse('$baseUrl/$targetUrl');

  Map<String, String> get headers {
    final h = <String, String>{'Accept': 'text/markdown'};
    if (apiKey != null && apiKey!.isNotEmpty) {
      h['Authorization'] = 'Bearer $apiKey';
    }
    return h;
  }

  Future<String?> fetch(String url) async {
    // SSRF guard: the target [url] is embedded in the reader path and fetched
    // server-side. Refuse internal targets before handing them to the reader.
    try {
      await _guard.validate(Uri.parse(url));
    } on SsrfBlockedException {
      return null;
    } catch (_) {
      // Unparseable target URL — treat as a miss.
      return null;
    }

    try {
      final response = await _client
          .get(buildReaderUrl(url), headers: headers)
          .timeout(Duration(seconds: timeoutSeconds));

      if (response.statusCode == 200) {
        return response.body;
      }
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
