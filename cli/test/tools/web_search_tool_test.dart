import 'package:test/test.dart';
import 'package:glue/src/tools/web_search_tool.dart';
import 'package:glue/src/web/search/search_router.dart';
import 'package:glue/src/web/search/models.dart';
import 'package:glue/src/web/search/provider.dart';

class _MockProvider implements WebSearchProvider {
  @override
  String get name => 'mock';
  @override
  bool get isConfigured => true;

  @override
  Future<WebSearchResponse> search(String query, {int maxResults = 5}) async {
    return WebSearchResponse(
      provider: 'mock',
      query: query,
      results: [
        WebSearchResult(
          title: 'Mock Result',
          url: Uri.parse('https://mock.com'),
          snippet: 'Mock snippet.',
        ),
      ],
    );
  }
}

void main() {
  group('WebSearchTool', () {
    late WebSearchTool tool;

    setUp(() {
      tool = WebSearchTool(SearchRouter([_MockProvider()]));
    });

    test('has correct name', () {
      expect(tool.name, 'web_search');
    });

    test('has query parameter', () {
      expect(tool.parameters.any((p) => p.name == 'query'), isTrue);
    });

    test('returns error for missing query', () async {
      final result = await tool.execute({});
      expect(result, contains('Error'));
    });

    test('returns formatted results', () async {
      final result = await tool.execute({'query': 'test search'});
      expect(result, contains('Mock Result'));
      expect(result, contains('mock.com'));
    });

    test('schema has correct structure', () {
      final schema = tool.toSchema();
      expect(schema['name'], 'web_search');
      expect(schema['input_schema']['properties'], contains('query'));
    });
  });
}
