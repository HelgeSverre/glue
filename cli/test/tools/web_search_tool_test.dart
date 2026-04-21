import 'package:glue/src/tools/web_search_tool.dart';
import 'package:glue/src/web/search/models.dart';
import 'package:glue/src/web/search/provider.dart';
import 'package:glue/src/web/search/search_router.dart';
import 'package:test/test.dart';

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
      final result = (await tool.execute({})).content;
      expect(result, contains('Error'));
    });

    test('returns formatted results', () async {
      final result = (await tool.execute({'query': 'test search'})).content;
      expect(result, contains('Mock Result'));
      expect(result, contains('mock.com'));
    });

    test('lazy constructor builds router only on first valid execute',
        () async {
      var buildCount = 0;
      final lazyTool = WebSearchTool.lazy(() {
        buildCount++;
        return SearchRouter([_MockProvider()]);
      });

      expect(buildCount, 0);

      final missingQuery = await lazyTool.execute({});
      expect(missingQuery.success, isFalse);
      expect(buildCount, 0);

      final first = await lazyTool.execute({'query': 'test search'});
      expect(first.success, isTrue);
      expect(first.content, contains('Mock Result'));
      expect(buildCount, 1);

      final second = await lazyTool.execute({'query': 'another search'});
      expect(second.success, isTrue);
      expect(buildCount, 1);
    });

    test('schema has correct structure', () {
      final schema = tool.toSchema();
      expect(schema['name'], 'web_search');
      final inputSchema = schema['input_schema'] as Map<String, dynamic>;
      expect(inputSchema['properties'], contains('query'));
    });

    test('provider description includes duckduckgo', () {
      final providerParameter =
          tool.parameters.firstWhere((p) => p.name == 'provider');
      expect(providerParameter.description, contains('duckduckgo'));
    });
  });
}
