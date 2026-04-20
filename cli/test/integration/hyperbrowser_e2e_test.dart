@Tags(['hyperbrowser'])
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'package:glue/src/tools/web_browser_tool.dart';
import 'package:glue/src/web/browser/browser_manager.dart';
import 'package:glue/src/web/browser/providers/hyperbrowser_provider.dart';

String? _hyperbrowserApiKey() {
  final envKey = Platform.environment['HYPERBROWSER_API_KEY'];
  if (envKey != null && envKey.isNotEmpty) return envKey;

  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) return null;

  final file = File('$home/.glue/config.yaml');
  if (!file.existsSync()) return null;

  final yaml = loadYaml(file.readAsStringSync());
  if (yaml is! YamlMap) return null;

  final web = yaml['web'];
  final browser = web is YamlMap ? web['browser'] : null;
  if (browser is! YamlMap) return null;

  final hyperbrowser = browser['hyperbrowser'];
  final nestedKey = hyperbrowser is YamlMap ? hyperbrowser['api_key'] : null;
  if (nestedKey is String && nestedKey.isNotEmpty) return nestedKey;

  final flatKey = browser['hyperbrowser_api_key'];
  if (flatKey is String && flatKey.isNotEmpty) return flatKey;

  return null;
}

void main() {
  group('Hyperbrowser e2e', () {
    test('provisions a session and drives web_browser over CDP', () async {
      final apiKey = _hyperbrowserApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        markTestSkipped(
          'Set HYPERBROWSER_API_KEY or web.browser.hyperbrowser.api_key in ~/.glue/config.yaml',
        );
        return;
      }

      final manager = BrowserManager(
        provider: HyperbrowserProvider(apiKey: apiKey),
      );
      final tool = WebBrowserTool(manager);

      try {
        final result = await tool.execute({
          'action': 'navigate',
          'url': 'https://example.com',
        });

        expect(result.success, isTrue);
        expect(result.content, contains('Navigated to: https://example.com'));
        expect(result.content, contains('Title: Example Domain'));
        expect(result.content, contains('Backend: hyperbrowser'));
      } finally {
        await tool.dispose();
      }
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
