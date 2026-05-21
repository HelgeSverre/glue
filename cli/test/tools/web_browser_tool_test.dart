import 'package:glue_harness/glue_harness.dart';
import 'package:glue_strategies/glue_strategies.dart';
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

    test('has optional wait_until parameter advertising the four values', () {
      final param = tool.parameters.firstWhere((p) => p.name == 'wait_until');
      expect(param.required, isFalse);
      expect(param.description, contains('load'));
      expect(param.description, contains('domcontentloaded'));
      expect(param.description, contains('networkalmostidle'));
      expect(param.description, contains('networkidle'));
    });

    test(
      'navigate rejects unknown wait_until value before opening browser',
      () async {
        var buildCount = 0;
        final lazyTool = WebBrowserTool.lazy(() {
          buildCount++;
          return BrowserManager(provider: _MockProvider());
        });

        final result = await lazyTool.execute({
          'action': 'navigate',
          'url': 'https://example.com',
          'wait_until': 'banana',
        });

        expect(result.content, contains('wait_until'));
        expect(result.content, contains('banana'));
        // Validation failure must not have provisioned a browser.
        expect(buildCount, 0);
      },
    );

    test(
      'navigate rejects non-string wait_until before opening browser',
      () async {
        var buildCount = 0;
        final lazyTool = WebBrowserTool.lazy(() {
          buildCount++;
          return BrowserManager(provider: _MockProvider());
        });

        final result = await lazyTool.execute({
          'action': 'navigate',
          'url': 'https://example.com',
          'wait_until': 42,
        });

        expect(result.content, contains('wait_until'));
        expect(result.content, contains('must be a string'));
        expect(buildCount, 0);
      },
    );

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

    test(
      'lazy constructor does not build manager for validation failures',
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
      },
    );

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
