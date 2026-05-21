import 'dart:async';

import 'package:puppeteer/puppeteer.dart' as pptr;

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';

/// Tool for browser-based web interaction via Chrome DevTools Protocol.
class WebBrowserTool extends Tool {
  final FutureOr<BrowserManager> Function() _managerProvider;
  BrowserManager? _manager;
  Future<BrowserManager>? _pendingManager;
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

  WebBrowserTool(BrowserManager manager) : this.lazy(() => manager);

  WebBrowserTool.lazy(this._managerProvider);

  @override
  String get name => 'web_browser';

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
      description:
          'Action to perform: navigate, screenshot, click, '
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
    ToolParameter(
      name: 'wait_until',
      type: 'string',
      description:
          'Navigation wait condition (optional, "navigate" only). '
          'One of: "load" (default — page load event fires), '
          '"domcontentloaded" (DOM parsed, fastest), '
          '"networkalmostidle" (≤2 in-flight requests for 500ms), '
          '"networkidle" (0 in-flight requests for 500ms — strict; '
          'often times out on ad/tracker-heavy sites).',
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
    final manager = _manager;
    if (manager != null) {
      await manager.dispose();
      return;
    }

    final pending = _pendingManager;
    if (pending != null) {
      await (await pending).dispose();
    }
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final action = args['action'];
    if (action is! String || action.isEmpty) {
      return ToolResult(
        success: false,
        content:
            'Error: no action provided. '
            'Valid actions: ${_validActions.join(", ")}',
      );
    }
    if (!_validActions.contains(action)) {
      return ToolResult(
        success: false,
        content:
            'Error: invalid action "$action". '
            'Valid actions: ${_validActions.join(", ")}',
        metadata: {'action': action},
      );
    }

    try {
      if (action == 'screenshot') {
        final parts = await _screenshotParts(args);
        final textPart = parts.whereType<TextPart>().firstOrNull;
        final imagePart = parts.whereType<ImagePart>().firstOrNull;
        return ToolResult(
          content: textPart?.text ?? 'Screenshot captured.',
          summary: 'web_browser: screenshot',
          contentParts: parts,
          metadata: {
            'action': action,
            if (imagePart != null) 'image_bytes': imagePart.bytes.length,
          },
        );
      }
      final text = await _dispatch(action, args);
      return ToolResult(
        content: text,
        summary: 'web_browser: $action',
        metadata: {'action': action},
      );
    } catch (e) {
      _page = null;
      _browser = null;
      return ToolResult(
        success: false,
        content: 'Error: $e',
        summary: 'web_browser: $action failed',
        metadata: {'action': action, 'error': e.toString()},
      );
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

    final manager = await _getManager();
    final endpoint = await manager.getEndpoint();
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

    final waitArg = args['wait_until'];
    final pptr.Until wait;
    if (waitArg == null) {
      // Default matches Playwright + the de-facto MCP browser-server
      // convention; `networkIdle` rarely resolves on ad/tracker-heavy
      // sites and was the cause of spurious 30s timeouts.
      wait = pptr.Until.load;
    } else if (waitArg is String) {
      final mapped = _parseWaitUntil(waitArg);
      if (mapped == null) {
        return 'Error: "wait_until" must be one of "load", '
            '"domcontentloaded", "networkalmostidle", "networkidle" '
            '(got "$waitArg").';
      }
      wait = mapped;
    } else {
      return 'Error: "wait_until" must be a string.';
    }

    final page = await _ensurePage();
    await page.goto(url, wait: wait);

    final title = await page.title;
    final manager = await _getManager();
    final endpoint = await manager.getEndpoint();
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

  Future<BrowserManager> _getManager() async {
    final manager = _manager;
    if (manager != null) return manager;

    final pending = _pendingManager;
    if (pending != null) return pending;

    final future = Future.sync(_managerProvider)
        .then((value) {
          _manager = value;
          return value;
        })
        .whenComplete(() {
          _pendingManager = null;
        });
    _pendingManager = future;
    return future;
  }

  /// Map the public `wait_until` string to Puppeteer's [pptr.Until]. Returns
  /// `null` for unknown values so the caller can surface a helpful error.
  ///
  /// Names follow the Playwright/Puppeteer convention (lowercase, no
  /// underscores) so they round-trip with the model's training data. We
  /// don't accept `networkidle0` / `networkidle2` aliases — those are
  /// JS-Puppeteer-specific shorthands and the Dart port uses
  /// `networkIdle` / `networkAlmostIdle` instead.
  static pptr.Until? _parseWaitUntil(String raw) {
    switch (raw.toLowerCase()) {
      case 'load':
        return pptr.Until.load;
      case 'domcontentloaded':
        return pptr.Until.domContentLoaded;
      case 'networkalmostidle':
        return pptr.Until.networkAlmostIdle;
      case 'networkidle':
        return pptr.Until.networkIdle;
      default:
        return null;
    }
  }
}
