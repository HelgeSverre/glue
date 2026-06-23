import 'dart:convert';

import 'package:glue_strategies/src/web/search/models.dart';
import 'package:glue_strategies/src/web/search/providers/http_search_provider.dart';

class TavilySearchProvider extends HttpSearchProvider {
  TavilySearchProvider({
    required super.apiKey,
    super.timeoutSeconds,
    super.client,
  });

  static const _baseUrl = 'https://api.tavily.com/search';

  @override
  String get name => 'tavily';

  @override
  String get apiLabel => 'Tavily API';

  @override
  String get notConfiguredMessage => 'Tavily API key not configured';

  @override
  HttpSearchRequest buildRequest(String query, int maxResults) {
    return HttpSearchRequest(
      uri: Uri.parse(_baseUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'query': query,
        'max_results': maxResults,
        'include_answer': true,
      }),
    );
  }

  @override
  WebSearchResponse parseResponseBody(
    Map<String, dynamic> json,
    String query,
  ) => parseResponse(json);

  static WebSearchResponse parseResponse(Map<String, dynamic> json) {
    final rawResults = (json['results'] as List<dynamic>?) ?? [];

    final results = rawResults.map((r) {
      final item = r as Map<String, dynamic>;
      return WebSearchResult(
        title: item['title'] as String? ?? '',
        url: Uri.parse(item['url'] as String? ?? ''),
        snippet: item['content'] as String? ?? '',
      );
    }).toList();

    return WebSearchResponse(
      provider: 'tavily',
      query: json['query'] as String? ?? '',
      results: results,
      aiSummary: json['answer'] as String?,
    );
  }
}
