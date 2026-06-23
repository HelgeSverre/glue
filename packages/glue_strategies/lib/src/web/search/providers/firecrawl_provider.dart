import 'dart:convert';

import 'package:glue_strategies/src/web/search/models.dart';
import 'package:glue_strategies/src/web/search/providers/http_search_provider.dart';

class FirecrawlSearchProvider extends HttpSearchProvider {
  FirecrawlSearchProvider({
    required super.apiKey,
    this.baseUrl = 'https://api.firecrawl.dev',
    super.timeoutSeconds,
    super.client,
  });

  final String baseUrl;

  @override
  String get name => 'firecrawl';

  @override
  String get apiLabel => 'Firecrawl API';

  @override
  String get notConfiguredMessage => 'Firecrawl API key not configured';

  @override
  HttpSearchRequest buildRequest(String query, int maxResults) {
    return HttpSearchRequest(
      uri: Uri.parse('$baseUrl/v1/search'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({'query': query, 'limit': maxResults}),
    );
  }

  @override
  WebSearchResponse parseResponseBody(
    Map<String, dynamic> json,
    String query,
  ) => parseResponse(json, query);

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
        snippet:
            item['description'] as String? ?? item['markdown'] as String? ?? '',
      );
    }).toList();

    return WebSearchResponse(
      provider: 'firecrawl',
      query: query,
      results: results,
    );
  }
}
