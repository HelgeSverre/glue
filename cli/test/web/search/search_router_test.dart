import 'package:test/test.dart';
import 'package:glue/src/web/search/search_router.dart';
import 'package:glue/src/web/search/models.dart';
import 'package:glue/src/web/search/provider.dart';

class _MockProvider implements WebSearchProvider {
  @override
  final String name;
  @override
  final bool isConfigured;
  final WebSearchResponse? response;
  final Exception? error;

  _MockProvider({
    required this.name,
    this.isConfigured = true,
    this.response,
    this.error,
  });

  @override
  Future<WebSearchResponse> search(String query, {int maxResults = 5}) async {
    if (error != null) throw error!;
    return response ??
        WebSearchResponse(provider: name, query: query, results: []);
  }
}

void main() {
  group('SearchRouter', () {
    test('selects first configured provider', () {
      final router = SearchRouter([
        _MockProvider(name: 'a', isConfigured: false),
        _MockProvider(name: 'b', isConfigured: true),
        _MockProvider(name: 'c', isConfigured: true),
      ]);
      expect(router.defaultProvider?.name, 'b');
    });

    test('returns null when no providers configured', () {
      final router = SearchRouter([
        _MockProvider(name: 'a', isConfigured: false),
      ]);
      expect(router.defaultProvider, isNull);
    });

    test('search uses default provider', () async {
      final response = WebSearchResponse(
        provider: 'mock',
        query: 'test',
        results: [
          WebSearchResult(
            title: 'Result',
            url: Uri.parse('https://r.com'),
            snippet: 'snip',
          ),
        ],
      );
      final router = SearchRouter([
        _MockProvider(name: 'mock', response: response),
      ]);
      final result = await router.search('test');
      expect(result.results, hasLength(1));
    });

    test('search falls back on error', () async {
      final fallbackResponse = WebSearchResponse(
        provider: 'fallback',
        query: 'test',
        results: [
          WebSearchResult(
            title: 'Fallback',
            url: Uri.parse('https://fb.com'),
            snippet: 'backup',
          ),
        ],
      );
      final router = SearchRouter([
        _MockProvider(name: 'primary', error: Exception('fail')),
        _MockProvider(name: 'fallback', response: fallbackResponse),
      ]);
      final result = await router.search('test');
      expect(result.provider, 'fallback');
    });

    test('search with explicit provider name', () async {
      final specificResponse = WebSearchResponse(
        provider: 'specific',
        query: 'test',
        results: [],
      );
      final router = SearchRouter([
        _MockProvider(name: 'default'),
        _MockProvider(name: 'specific', response: specificResponse),
      ]);
      final result = await router.search('test', providerName: 'specific');
      expect(result.provider, 'specific');
    });

    test('throws when no provider available', () async {
      final router = SearchRouter([
        _MockProvider(name: 'a', isConfigured: false),
      ]);
      expect(
        () => router.search('test'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
