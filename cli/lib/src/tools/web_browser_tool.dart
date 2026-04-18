import 'package:puppeteer/puppeteer.dart' as pptr;

import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/web/browser/browser_manager.dart';
import 'package:glue/src/web/fetch/html_extractor.dart';
import 'package:glue/src/web/fetch/html_to_markdown.dart';
import 'package:glue/src/web/fetch/truncation.dart';

/// Tool for browser-based web interaction via Chrome DevTools Protocol.
class WebBrowserTool extends Tool {
  final BrowserManager _manager;
  pptr.Browser? _browser;
  pptr.Page? _page;

  static const _validActions = {
    'navigate',
    'screenshot',
    'click',
    'type',
    'extract_text',
    'evaluate',
  };

  WebBrowserTool(this._manager);

  @override
  String get name => 'web_browser';

  @override
  ToolGroup get group => ToolGroup.mcp;

  @override
  String get description =>
      'Control a browser to interact with web pages that require JavaScript, '
      'authentication, or dynamic content. Supports navigation, screenshots, '
      'clicking elements, typing text, extracting page text, and evaluating '
      'JavaScript. The browser session persists across calls.';

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'action',
          type: 'string',
          description: 'Action to perform: navigate, screenshot, click, '
              'type, extract_text, or evaluate.',
        ),
        ToolParameter(
          name: 'url',
          type: 'string',
          description: 'URL to navigate to (required for "navigate" action).',
          required: false,
        ),
        ToolParameter(
          name: 'selector',
          type: 'string',
          description:
              'CSS selector for the target element (required for "click" '
              'and "type" actions, optional for "screenshot").',
          required: false,
        ),
        ToolParameter(
          name: 'text',
          type: 'string',
          description: 'Text to type (required for "type" action).',
          required: false,
        ),
        ToolParameter(
          name: 'javascript',
          type: 'string',
          description:
              'JavaScript code to evaluate (required for "evaluate" action).',
          required: false,
        ),
      ];

  @override
  Future<void> dispose() async {
    try {
      await _page?.close();
    } catch (_) {}
    _page = null;
    try {
      await _browser?.close();
    } catch (_) {}
    _browser = null;
    await _manager.dispose();
  }

  @override
  Future<List<ContentPart>> execute(Map<String, dynamic> args) async {
    final action = args['action'];
    if (action is! String || action.isEmpty) {
      return [
        TextPart('Error: no action provided. '
            'Valid actions: ${_validActions.join(", ")}')
      ];
    }
    if (!_validActions.contains(action)) {
      return [
        TextPart('Error: invalid action "$action". '
            'Valid actions: ${_validActions.join(", ")}')
      ];
    }

    try {
      if (action == 'screenshot') {
        return await _screenshotParts(args);
      }
      final text = await _dispatch(action, args);
      return [TextPart(text)];
    } catch (e) {
      _page = null;
      _browser = null;
      return [TextPart('Error: $e')];
    }
  }

  Future<List<ContentPart>> _screenshotParts(Map<String, dynamic> args) async {
    final page = await _ensurePage();
    final selector = args['selector'] as String?;

    List<int> bytes;
    if (selector != null && selector.isNotEmpty) {
      final element = await page.$(selector);
      bytes = await element.screenshot();
    } else {
      bytes = await page.screenshot();
    }

    return [
      TextPart('Screenshot captured (${bytes.length} bytes).'),
      ImagePart(bytes: bytes, mimeType: 'image/png'),
    ];
  }

  Future<String> _dispatch(String action, Map<String, dynamic> args) async {
    return switch (action) {
      'navigate' => _navigate(args),
      'click' => _click(args),
      'type' => _type(args),
      'extract_text' => _extractText(args),
      'evaluate' => _evaluate(args),
      _ => 'Error: unknown action "$action"',
    };
  }

  Future<pptr.Page> _ensurePage() async {
    if (_page != null) return _page!;

    final endpoint = await _manager.getEndpoint();
    _browser = await pptr.puppeteer.connect(
      browserWsEndpoint: endpoint.cdpWsUrl,
    );
    _page = await _browser!.newPage();
    return _page!;
  }

  Future<String> _navigate(Map<String, dynamic> args) async {
    final url = args['url'];
    if (url is! String || url.isEmpty) {
      return 'Error: "navigate" action requires a "url" parameter';
    }

    final page = await _ensurePage();
    await page.goto(url, wait: pptr.Until.networkIdle);

    final title = await page.title;
    final endpoint = await _manager.getEndpoint();
    final buf = StringBuffer();
    buf.writeln('Navigated to: $url');
    if (title != null && title.isNotEmpty) buf.writeln('Title: $title');
    buf.writeln(endpoint.debugFooter);
    return buf.toString();
  }

  Future<String> _click(Map<String, dynamic> args) async {
    final selector = args['selector'];
    if (selector is! String || selector.isEmpty) {
      return 'Error: "click" action requires a "selector" parameter';
    }

    final page = await _ensurePage();
    await page.click(selector);
    await Future.delayed(const Duration(milliseconds: 500));

    final title = await page.title;
    return 'Clicked element: $selector\nCurrent page: $title';
  }

  Future<String> _type(Map<String, dynamic> args) async {
    final selector = args['selector'];
    final text = args['text'];
    if (selector is! String || selector.isEmpty) {
      return 'Error: "type" action requires a "selector" parameter';
    }
    if (text is! String || text.isEmpty) {
      return 'Error: "type" action requires a "text" parameter';
    }

    final page = await _ensurePage();
    await page.type(selector, text);
    return 'Typed "$text" into element: $selector';
  }

  Future<String> _extractText(Map<String, dynamic> args) async {
    final page = await _ensurePage();
    final html = await page.content;
    if (html == null || html.isEmpty) return 'Error: page has no content';

    final extracted = HtmlExtractor.extract(html);
    final markdown = HtmlToMarkdown.convert(extracted);
    final truncated = TokenTruncation.truncate(markdown, maxTokens: 50000);
    return truncated;
  }

  Future<String> _evaluate(Map<String, dynamic> args) async {
    final js = args['javascript'];
    if (js is! String || js.isEmpty) {
      return 'Error: "evaluate" action requires a "javascript" parameter';
    }

    final page = await _ensurePage();
    final result = await page.evaluate<dynamic>(js);
    if (result == null) return 'null';
    return result.toString();
  }
}
