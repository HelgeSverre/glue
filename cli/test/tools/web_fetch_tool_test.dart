import 'package:test/test.dart';
import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/tools/web_fetch_tool.dart';
import 'package:glue/src/web/web_config.dart';

void main() {
  group('WebFetchTool', () {
    late WebFetchTool tool;

    setUp(() {
      tool = WebFetchTool(const WebFetchConfig(allowJinaFallback: false));
    });

    test('has correct name', () {
      expect(tool.name, 'web_fetch');
    });

    test('has url parameter', () {
      expect(tool.parameters.any((p) => p.name == 'url'), isTrue);
    });

    test('has max_tokens parameter', () {
      expect(tool.parameters.any((p) => p.name == 'max_tokens'), isTrue);
    });

    test('returns error for missing url', () async {
      final result = ContentPart.textOnly(await tool.execute({}));
      expect(result, contains('Error'));
    });

    test('returns error for invalid url', () async {
      final result =
          ContentPart.textOnly(await tool.execute({'url': 'not-a-url'}));
      expect(result, contains('Invalid URL'));
    });

    test('schema has correct structure', () {
      final schema = tool.toSchema();
      expect(schema['name'], 'web_fetch');
      final inputSchema = schema['input_schema'] as Map<String, dynamic>;
      expect(inputSchema['properties'], contains('url'));
    });
  });
}
