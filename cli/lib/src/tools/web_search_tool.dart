import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/web/search/search_router.dart';

class WebSearchTool extends Tool {
  final SearchRouter _router;

  WebSearchTool(this._router);

  @override
  String get name => 'web_search';

  @override
  String get description =>
      'Search the web for information. Returns titles, URLs, and '
      'snippets from search results. Use web_fetch to read full '
      'content from a specific URL found in search results.';

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'query',
          type: 'string',
          description: 'The search query.',
        ),
        ToolParameter(
          name: 'max_results',
          type: 'integer',
          description: 'Maximum number of results to return (default: 5).',
          required: false,
        ),
        ToolParameter(
          name: 'provider',
          type: 'string',
          description:
              'Search provider to use: "brave", "tavily", or "firecrawl". '
              'Defaults to auto-detect from configured API keys.',
          required: false,
        ),
      ];

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final query = args['query'];
    if (query is! String || query.isEmpty) {
      return ToolResult(
        success: false,
        content: 'Error: no query provided',
      );
    }

    final maxResults = (args['max_results'] as num?)?.toInt() ?? 5;
    final providerName = args['provider'] as String?;

    try {
      final response = await _router.search(
        query,
        maxResults: maxResults,
        providerName: providerName,
      );
      final text = response.toText();
      return ToolResult(
        content: text,
        summary: 'web_search: $query',
        metadata: {
          'query': query,
          'max_results': maxResults,
          if (providerName != null) 'provider': providerName,
        },
      );
    } catch (e) {
      return ToolResult(
        success: false,
        content: 'Error: $e',
        summary: 'web_search failed: $query',
        metadata: {'query': query, 'error': e.toString()},
      );
    }
  }
}
