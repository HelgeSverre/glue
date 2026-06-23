import 'package:glue_strategies/src/web/search/models.dart';
import 'package:glue_strategies/src/web/search/providers/http_search_provider.dart';

class BraveSearchProvider extends HttpSearchProvider {
  BraveSearchProvider({
    required super.apiKey,
    super.timeoutSeconds,
    super.client,
  });

  static const _baseUrl = 'https://api.search.brave.com/res/v1/web/search';

  @override
  String get name => 'brave';

  @override
  String get apiLabel => 'Brave Search API';

  @override
  String get notConfiguredMessage => 'Brave Search API key not configured';

  @override
  HttpSearchRequest buildRequest(String query, int maxResults) {
    return HttpSearchRequest(
      uri: Uri.parse(
        _baseUrl,
      ).replace(queryParameters: {'q': query, 'count': maxResults.toString()}),
      headers: {
        'Accept': 'application/json',
        'Accept-Encoding': 'gzip',
        'X-Subscription-Token': apiKey!,
      },
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

    return WebSearchResponse(provider: 'brave', query: query, results: results);
  }
}
