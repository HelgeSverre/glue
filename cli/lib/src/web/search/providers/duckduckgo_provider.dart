import 'dart:async';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import 'package:glue/src/web/search/models.dart';
import 'package:glue/src/web/search/provider.dart';

class DuckDuckGoSearchProvider implements WebSearchProvider {
  final int timeoutSeconds;
  static const _baseUrl = 'https://html.duckduckgo.com/html/';

  DuckDuckGoSearchProvider({
    this.timeoutSeconds = 15,
  });

  @override
  String get name => 'duckduckgo';

  @override
  bool get isConfigured => true;

  @override
  Future<WebSearchResponse> search(
    String query, {
    int maxResults = 5,
  }) async {
    final response = await http.get(
      Uri.parse(_baseUrl).replace(queryParameters: {
        'q': query,
      }),
      headers: {
        'Accept': 'text/html,application/xhtml+xml',
      },
    ).timeout(Duration(seconds: timeoutSeconds));

    if (response.statusCode != 200) {
      throw Exception(
        'DuckDuckGo search returned ${response.statusCode}: '
        '${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
      );
    }

    final parsed = parseHtml(response.body, query);
    return WebSearchResponse(
      provider: parsed.provider,
      query: parsed.query,
      results: parsed.results.take(maxResults).toList(),
      aiSummary: parsed.aiSummary,
    );
  }

  static WebSearchResponse parseHtml(String body, String query) {
    final document = html.parse(body);
    final titleNodes = document.querySelectorAll('.result__a');
    final snippetNodes = document.querySelectorAll('.result__snippet');

    final results = <WebSearchResult>[];
    for (var i = 0; i < titleNodes.length; i++) {
      final node = titleNodes[i];
      final href = node.attributes['href'];
      if (href == null || href.isEmpty) continue;

      final url = _resolveUrl(href);
      if (url == null) continue;

      final snippet =
          i < snippetNodes.length ? snippetNodes[i].text.trim() : '';
      results.add(
        WebSearchResult(
          title: node.text.trim(),
          url: url,
          snippet: snippet,
        ),
      );
    }

    return WebSearchResponse(
      provider: 'duckduckgo',
      query: query,
      results: results,
    );
  }

  static Uri? _resolveUrl(String href) {
    final absoluteHref = href.startsWith('//') ? 'https:$href' : href;
    final uri = Uri.tryParse(absoluteHref);
    if (uri == null) return null;

    final uddg = uri.queryParameters['uddg'];
    if (uddg != null && uddg.isNotEmpty) {
      return Uri.tryParse(Uri.decodeComponent(uddg));
    }

    return uri;
  }
}
