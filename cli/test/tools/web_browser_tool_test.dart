import 'package:glue/src/tools/web_browser_tool.dart';
import 'package:glue/src/web/browser/browser_endpoint.dart';
import 'package:glue/src/web/browser/browser_manager.dart';
import 'package:test/test.dart';

class _MockProvider implements BrowserEndpointProvider {
  @override
  String get name => 'mock';

  @override
  bool get isConfigured => true;

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
      final result = (await tool.execute({})).content;
      expect(result, contains('Error'));
    });

    test('returns error for invalid action', () async {
      final result = (await tool.execute({'action': 'invalid'})).content;
      expect(result, contains('Error'));
      expect(result, contains('invalid'));
    });

    test('navigate requires url', () async {
      final result = (await tool.execute({'action': 'navigate'})).content;
      expect(result, contains('Error'));
      expect(result, contains('url'));
    });

    test('click requires selector', () async {
      final result = (await tool.execute({'action': 'click'})).content;
      expect(result, contains('Error'));
      expect(result, contains('selector'));
    });

    test('lazy constructor does not build manager for validation failures',
        () async {
      var buildCount = 0;
      final lazyTool = WebBrowserTool.lazy(() {
        buildCount++;
        return BrowserManager(provider: _MockProvider());
      });

      expect(buildCount, 0);

      final missingAction = await lazyTool.execute({});
      expect(missingAction.success, isFalse);
      expect(buildCount, 0);

      final invalidAction = await lazyTool.execute({'action': 'invalid'});
      expect(invalidAction.success, isFalse);
      expect(buildCount, 0);

      final missingUrl = await lazyTool.execute({'action': 'navigate'});
      expect(missingUrl.content, contains('url'));
      expect(buildCount, 0);
    });

    test('dispose before first use does not build manager', () async {
      var buildCount = 0;
      final lazyTool = WebBrowserTool.lazy(() {
        buildCount++;
        return BrowserManager(provider: _MockProvider());
      });

      await lazyTool.dispose();

      expect(buildCount, 0);
    });
  });
}
