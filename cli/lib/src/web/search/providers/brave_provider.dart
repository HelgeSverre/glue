import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:glue/src/web/search/models.dart';
import 'package:glue/src/web/search/provider.dart';
import 'package:glue/src/utils.dart';

class BraveSearchProvider implements WebSearchProvider {
  final String? apiKey;
  final int timeoutSeconds;
  final http.Client _client;
  static const _baseUrl = 'https://api.search.brave.com/res/v1/web/search';

  BraveSearchProvider({
    required this.apiKey,
    this.timeoutSeconds = 15,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  String get name => 'brave';

  @override
  bool get isConfigured => apiKey != null && apiKey!.isNotEmpty;

  @override
  Future<WebSearchResponse> search(
    String query, {
    int maxResults = 5,
  }) async {
    if (!isConfigured) {
      throw StateError('Brave Search API key not configured');
    }

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'q': query,
      'count': maxResults.toString(),
    });

    final response = await _client.get(uri, headers: {
      'Accept': 'application/json',
      'Accept-Encoding': 'gzip',
      'X-Subscription-Token': apiKey!,
    }).timeout(timeoutSeconds.seconds);

    if (response.statusCode != 200) {
      throw HttpException(
        'Brave Search API returned ${response.statusCode}: '
        '${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return parseResponse(json, query);
  }

  static WebSearchResponse parseResponse(
    Map<String, dynamic> json,
    String query,
  ) {
    final web = json['web'] as Map<String, dynamic>?;
    final rawResults = (web?['results'] as List<dynamic>?) ?? [];

    final results = rawResults.map((r) {
      final item = r as Map<String, dynamic>;
      return WebSearchResult(
        title: item['title'] as String? ?? '',
        url: Uri.parse(item['url'] as String? ?? ''),
        snippet: item['description'] as String? ?? '',
      );
    }).toList();

    return WebSearchResponse(
      provider: 'brave',
      query: query,
      results: results,
    );
  }
}

class HttpException implements Exception {
  final String message;
  HttpException(this.message);
  @override
  String toString() => 'HttpException: $message';
}
