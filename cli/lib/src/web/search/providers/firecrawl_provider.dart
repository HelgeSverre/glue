import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:glue/src/web/search/models.dart';
import 'package:glue/src/web/search/provider.dart';

class FirecrawlSearchProvider implements WebSearchProvider {
  final String? apiKey;
  final String baseUrl;
  final int timeoutSeconds;

  FirecrawlSearchProvider({
    required this.apiKey,
    this.baseUrl = 'https://api.firecrawl.dev',
    this.timeoutSeconds = 15,
  });

  @override
  String get name => 'firecrawl';

  @override
  bool get isConfigured => apiKey != null && apiKey!.isNotEmpty;

  @override
  Future<WebSearchResponse> search(
    String query, {
    int maxResults = 5,
  }) async {
    if (!isConfigured) {
      throw StateError('Firecrawl API key not configured');
    }

    final response = await http
        .post(
          Uri.parse('$baseUrl/v1/search'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'query': query,
            'limit': maxResults,
          }),
        )
        .timeout(Duration(seconds: timeoutSeconds));

    if (response.statusCode != 200) {
      throw Exception(
        'Firecrawl API returned ${response.statusCode}: '
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
    final rawResults = (json['data'] as List<dynamic>?) ?? [];

    final results = rawResults.map((r) {
      final item = r as Map<String, dynamic>;
      return WebSearchResult(
        title: item['title'] as String? ?? '',
        url: Uri.parse(item['url'] as String? ?? ''),
        snippet: item['description'] as String? ??
            item['markdown'] as String? ??
            '',
      );
    }).toList();

    return WebSearchResponse(
      provider: 'firecrawl',
      query: query,
      results: results,
    );
  }
}
