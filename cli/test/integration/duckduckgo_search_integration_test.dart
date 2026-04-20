@Tags(['integration'])
library;

import 'package:test/test.dart';
import 'package:glue/src/web/search/providers/duckduckgo_provider.dart';

void main() {
  group('DuckDuckGo search integration', () {
    test('returns live results for a simple query', () async {
      final provider = DuckDuckGoSearchProvider();

      final response = await provider.search('helge sverre', maxResults: 3);

      expect(response.provider, 'duckduckgo');
      expect(response.query, 'helge sverre');
      expect(response.results, isNotEmpty);
      expect(
        response.results.any((result) =>
            result.title.isNotEmpty &&
            result.url.toString().startsWith('http')),
        isTrue,
      );
    });
  });
}
