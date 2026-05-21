@Tags(['integration'])
library;

import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

void main() {
  group('DuckDuckGo search integration', () {
    test('returns live results for a simple query', () async {
      final provider = DuckDuckGoSearchProvider();

      final response = await provider.search('helge sverre', maxResults: 3);

      expect(response.provider, 'duckduckgo');
      expect(response.query, 'helge sverre');
      expect(response.results, isNotEmpty);
      expect(
        response.results.any(
          (result) =>
              result.title.isNotEmpty &&
              result.url.toString().startsWith('http'),
        ),
        isTrue,
      );
    });
  });
}
