import 'package:test/test.dart';
import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/tools/web_browser_tool.dart';
import 'package:glue/src/web/browser/browser_manager.dart';
import 'package:glue/src/web/browser/browser_endpoint.dart';

class _MockProvider implements BrowserEndpointProvider {
  @override
  String get name => 'mock';
  @override
  bool get isAvailable => true;

  @override
  Future<BrowserEndpoint> provision() async => BrowserEndpoint(
        cdpWsUrl: 'ws://localhost:9222/devtools/browser/mock',
        backendName: 'mock',
      );
}

void main() {
  group('WebBrowserTool', () {
    late WebBrowserTool tool;

    setUp(() {
      tool = WebBrowserTool(BrowserManager(provider: _MockProvider()));
    });

    test('has correct name', () {
      expect(tool.name, 'web_browser');
    });

    test('has action parameter', () {
      expect(tool.parameters.any((p) => p.name == 'action'), isTrue);
    });

    test('has url parameter', () {
      expect(tool.parameters.any((p) => p.name == 'url'), isTrue);
    });

    test('has selector parameter', () {
      expect(tool.parameters.any((p) => p.name == 'selector'), isTrue);
    });

    test('returns error for missing action', () async {
      final result = ContentPart.textOnly(await tool.execute({}));
      expect(result, contains('Error'));
    });

    test('returns error for invalid action', () async {
      final result =
          ContentPart.textOnly(await tool.execute({'action': 'invalid'}));
      expect(result, contains('Error'));
      expect(result, contains('invalid'));
    });

    test('navigate requires url', () async {
      final result =
          ContentPart.textOnly(await tool.execute({'action': 'navigate'}));
      expect(result, contains('Error'));
      expect(result, contains('url'));
    });

    test('click requires selector', () async {
      final result =
          ContentPart.textOnly(await tool.execute({'action': 'click'}));
      expect(result, contains('Error'));
      expect(result, contains('selector'));
    });
  });
}
