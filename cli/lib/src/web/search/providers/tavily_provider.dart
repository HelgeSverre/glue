import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:glue/src/web/search/models.dart';
import 'package:glue/src/web/search/provider.dart';
import 'package:glue/src/utils.dart';

class TavilySearchProvider implements WebSearchProvider {
  final String? apiKey;
  final int timeoutSeconds;
  final http.Client _client;
  static const _baseUrl = 'https://api.tavily.com/search';

  TavilySearchProvider({
    required this.apiKey,
    this.timeoutSeconds = 15,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  String get name => 'tavily';

  @override
  bool get isConfigured => apiKey != null && apiKey!.isNotEmpty;

  @override
  Future<WebSearchResponse> search(
    String query, {
    int maxResults = 5,
  }) async {
    if (!isConfigured) {
      throw StateError('Tavily API key not configured');
    }

    final response = await _client
        .post(
          Uri.parse(_baseUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'query': query,
            'max_results': maxResults,
            'include_answer': true,
          }),
        )
        .timeout(timeoutSeconds.seconds);

    if (response.statusCode != 200) {
      throw Exception(
        'Tavily API returned ${response.statusCode}: '
        '${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return parseResponse(json);
  }

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
