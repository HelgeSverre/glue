# Web Tools Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `web_fetch` and `web_search` tools to Glue — pure Dart, configurable providers, unified data models.

**Architecture:** Three layers: (1) pure Dart library code in `lib/src/web/` with provider interfaces, HTTP clients, HTML extraction, and markdown conversion; (2) thin `Tool` wrappers in `lib/src/tools/` that delegate to the library; (3) config integration via `GlueConfig`. Provider pattern with auto-detection and fallback. Web browser tool deferred to future phase.

**Tech Stack:** Dart 3.4+, `package:html` (DOM parsing), `package:http` (already in deps), existing `Tool` base class, existing `GlueConfig` pattern.

---

## Phase 1: Core Infrastructure

### Task 1: Add `package:html` dependency

**Files:**
- Modify: `cli/pubspec.yaml`

**Step 1: Add the dependency**

Add `html: ^0.15.5` to pubspec.yaml dependencies:

```yaml
dependencies:
  args: ^2.7.0
  html: ^0.15.5
  http: ^1.6.0
  path: ^1.9.1
  yaml: ^3.1.3
  crypto: ^3.0.7
```

**Step 2: Install**

Run: `cd cli && dart pub get`
Expected: resolves successfully

**Step 3: Verify**

Run: `dart analyze`
Expected: no new warnings

**Step 4: Commit**

```bash
git add cli/pubspec.yaml cli/pubspec.lock
git commit -m "deps: add package:html for web_fetch HTML parsing"
```

---

### Task 2: Web config model + constants

**Files:**
- Modify: `cli/lib/src/config/constants.dart`
- Create: `cli/lib/src/web/web_config.dart`
- Test: `cli/test/web/web_config_test.dart`

**Step 1: Add web constants to `AppConstants`**

Add to `cli/lib/src/config/constants.dart` inside the class body:

```dart
  // Web tool configuration
  static const int webFetchTimeoutSeconds = 30;
  static const int webFetchMaxBytes = 5 * 1024 * 1024; // 5MB
  static const int webFetchDefaultMaxTokens = 50000;
  static const int webSearchTimeoutSeconds = 15;
  static const int webSearchDefaultMaxResults = 5;
```

**Step 2: Create `WebConfig` model**

Create `cli/lib/src/web/web_config.dart`:

```dart
import '../config/constants.dart';

/// Configuration for web_fetch tool.
class WebFetchConfig {
  final int timeoutSeconds;
  final int maxBytes;
  final int defaultMaxTokens;
  final String? jinaApiKey;
  final String jinaBaseUrl;
  final bool allowJinaFallback;

  const WebFetchConfig({
    this.timeoutSeconds = AppConstants.webFetchTimeoutSeconds,
    this.maxBytes = AppConstants.webFetchMaxBytes,
    this.defaultMaxTokens = AppConstants.webFetchDefaultMaxTokens,
    this.jinaApiKey,
    this.jinaBaseUrl = 'https://r.jina.ai',
    this.allowJinaFallback = true,
  });
}

/// Supported web search providers.
enum WebSearchProviderType { brave, tavily, firecrawl }

/// Configuration for web_search tool.
class WebSearchConfig {
  final WebSearchProviderType? provider;
  final int timeoutSeconds;
  final int defaultMaxResults;
  final String? braveApiKey;
  final String? tavilyApiKey;
  final String? firecrawlApiKey;
  final String? firecrawlBaseUrl;

  const WebSearchConfig({
    this.provider,
    this.timeoutSeconds = AppConstants.webSearchTimeoutSeconds,
    this.defaultMaxResults = AppConstants.webSearchDefaultMaxResults,
    this.braveApiKey,
    this.tavilyApiKey,
    this.firecrawlApiKey,
    this.firecrawlBaseUrl,
  });

  /// Auto-detect provider from available API keys.
  /// Priority: brave → tavily → firecrawl.
  WebSearchProviderType? get resolvedProvider {
    if (provider != null) return provider;
    if (braveApiKey != null && braveApiKey!.isNotEmpty) {
      return WebSearchProviderType.brave;
    }
    if (tavilyApiKey != null && tavilyApiKey!.isNotEmpty) {
      return WebSearchProviderType.tavily;
    }
    if (firecrawlApiKey != null && firecrawlApiKey!.isNotEmpty) {
      return WebSearchProviderType.firecrawl;
    }
    return null;
  }
}

/// Combined web configuration.
class WebConfig {
  final WebFetchConfig fetch;
  final WebSearchConfig search;

  const WebConfig({
    this.fetch = const WebFetchConfig(),
    this.search = const WebSearchConfig(),
  });
}
```

**Step 3: Write test**

Create `cli/test/web/web_config_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:glue/src/web/web_config.dart';

void main() {
  group('WebSearchConfig', () {
    test('resolvedProvider returns null when no keys set', () {
      const config = WebSearchConfig();
      expect(config.resolvedProvider, isNull);
    });

    test('resolvedProvider prefers brave over tavily', () {
      const config = WebSearchConfig(
        braveApiKey: 'key1',
        tavilyApiKey: 'key2',
      );
      expect(config.resolvedProvider, WebSearchProviderType.brave);
    });

    test('resolvedProvider falls back to tavily', () {
      const config = WebSearchConfig(tavilyApiKey: 'key');
      expect(config.resolvedProvider, WebSearchProviderType.tavily);
    });

    test('resolvedProvider falls back to firecrawl', () {
      const config = WebSearchConfig(firecrawlApiKey: 'key');
      expect(config.resolvedProvider, WebSearchProviderType.firecrawl);
    });

    test('explicit provider overrides auto-detection', () {
      const config = WebSearchConfig(
        provider: WebSearchProviderType.firecrawl,
        braveApiKey: 'key',
      );
      expect(config.resolvedProvider, WebSearchProviderType.firecrawl);
    });

    test('empty string key is treated as not set', () {
      const config = WebSearchConfig(braveApiKey: '');
      expect(config.resolvedProvider, isNull);
    });
  });

  group('WebFetchConfig', () {
    test('defaults are sensible', () {
      const config = WebFetchConfig();
      expect(config.timeoutSeconds, 30);
      expect(config.maxBytes, 5 * 1024 * 1024);
      expect(config.defaultMaxTokens, 50000);
      expect(config.allowJinaFallback, isTrue);
    });
  });
}
```

**Step 4: Run tests**

Run: `cd cli && dart test test/web/web_config_test.dart`
Expected: all pass

**Step 5: Commit**

```bash
git add cli/lib/src/config/constants.dart cli/lib/src/web/web_config.dart cli/test/web/web_config_test.dart
git commit -m "feat(web): add WebConfig model with provider auto-detection"
```

---

### Task 3: Wire `WebConfig` into `GlueConfig`

**Files:**
- Modify: `cli/lib/src/config/glue_config.dart`
- Modify: `cli/test/config/glue_config_test.dart` (if exists, otherwise create)

**Step 1: Add `WebConfig` field to `GlueConfig`**

Add import at top of `glue_config.dart`:
```dart
import '../web/web_config.dart';
```

Add field to `GlueConfig` class:
```dart
final WebConfig webConfig;
```

Add to constructor with default:
```dart
WebConfig? webConfig,
```
And in the initializer list:
```dart
webConfig = webConfig ?? const WebConfig(),
```

**Step 2: Load web config from env/file in `GlueConfig.load()`**

Inside the `factory GlueConfig.load()` method, after the Docker config section and before the profiles section, add:

```dart
    // 2d. Resolve web configuration.
    final webSection = fileConfig?['web'] as Map?;
    final fetchSection = webSection?['fetch'] as Map?;
    final searchSection = webSection?['search'] as Map?;

    final jinaApiKey = Platform.environment['JINA_API_KEY'] ??
        fetchSection?['jina_api_key'] as String?;
    final braveApiKey = Platform.environment['BRAVE_API_KEY'] ??
        searchSection?['brave_api_key'] as String?;
    final tavilyApiKey = Platform.environment['TAVILY_API_KEY'] ??
        searchSection?['tavily_api_key'] as String?;
    final firecrawlApiKey = Platform.environment['FIRECRAWL_API_KEY'] ??
        searchSection?['firecrawl_api_key'] as String?;

    final searchProviderStr = Platform.environment['GLUE_SEARCH_PROVIDER'] ??
        searchSection?['provider'] as String?;
    final searchProvider = searchProviderStr != null
        ? WebSearchProviderType.values.firstWhere(
            (p) => p.name == searchProviderStr,
            orElse: () => WebSearchProviderType.brave,
          )
        : null;

    final webFetchConfig = WebFetchConfig(
      jinaApiKey: jinaApiKey,
      allowJinaFallback:
          fetchSection?['allow_jina_fallback'] as bool? ?? true,
      timeoutSeconds: fetchSection?['timeout_seconds'] as int? ??
          AppConstants.webFetchTimeoutSeconds,
      maxBytes: fetchSection?['max_bytes'] as int? ??
          AppConstants.webFetchMaxBytes,
      defaultMaxTokens: fetchSection?['max_tokens'] as int? ??
          AppConstants.webFetchDefaultMaxTokens,
    );

    final webSearchConfig = WebSearchConfig(
      provider: searchProvider,
      braveApiKey: braveApiKey,
      tavilyApiKey: tavilyApiKey,
      firecrawlApiKey: firecrawlApiKey,
      firecrawlBaseUrl: searchSection?['firecrawl_base_url'] as String?,
      timeoutSeconds: searchSection?['timeout_seconds'] as int? ??
          AppConstants.webSearchTimeoutSeconds,
      defaultMaxResults: searchSection?['max_results'] as int? ??
          AppConstants.webSearchDefaultMaxResults,
    );

    final webConfig = WebConfig(
      fetch: webFetchConfig,
      search: webSearchConfig,
    );
```

Pass `webConfig: webConfig` to the `GlueConfig(...)` constructor call at the end.

**Step 3: Run tests**

Run: `cd cli && dart analyze && dart test`
Expected: zero warnings, all tests pass

**Step 4: Commit**

```bash
git add cli/lib/src/config/glue_config.dart
git commit -m "feat(config): wire WebConfig into GlueConfig with env/file resolution"
```

---

## Phase 2: `web_fetch` Tool

### Task 4: HTML content extractor (Readability-style)

**Files:**
- Create: `cli/lib/src/web/fetch/html_extractor.dart`
- Test: `cli/test/web/fetch/html_extractor_test.dart`

**Step 1: Write failing tests**

Create `cli/test/web/fetch/html_extractor_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:glue/src/web/fetch/html_extractor.dart';

void main() {
  group('HtmlExtractor', () {
    test('extracts article content from page', () {
      const html = '''
      <html><body>
        <nav><a href="/">Home</a><a href="/about">About</a></nav>
        <article>
          <h1>Hello World</h1>
          <p>This is the main content of the article.</p>
          <p>It has multiple paragraphs with useful information.</p>
        </article>
        <footer>Copyright 2026</footer>
      </body></html>
      ''';

      final result = HtmlExtractor.extract(html);
      expect(result, contains('Hello World'));
      expect(result, contains('main content'));
      expect(result, isNot(contains('Copyright')));
      expect(result, isNot(contains('Home')));
    });

    test('extracts main element when no article', () {
      const html = '''
      <html><body>
        <nav>Navigation</nav>
        <main><h1>Title</h1><p>Content here.</p></main>
        <aside>Sidebar</aside>
      </body></html>
      ''';

      final result = HtmlExtractor.extract(html);
      expect(result, contains('Title'));
      expect(result, contains('Content here'));
      expect(result, isNot(contains('Navigation')));
      expect(result, isNot(contains('Sidebar')));
    });

    test('falls back to body when no semantic containers', () {
      const html = '''
      <html><body>
        <h1>Simple Page</h1>
        <p>Just some text.</p>
      </body></html>
      ''';

      final result = HtmlExtractor.extract(html);
      expect(result, contains('Simple Page'));
      expect(result, contains('Just some text'));
    });

    test('strips script and style tags', () {
      const html = '''
      <html><body>
        <script>alert("bad")</script>
        <style>.x { color: red; }</style>
        <p>Clean content.</p>
      </body></html>
      ''';

      final result = HtmlExtractor.extract(html);
      expect(result, contains('Clean content'));
      expect(result, isNot(contains('alert')));
      expect(result, isNot(contains('color')));
    });

    test('returns empty string for empty/invalid HTML', () {
      expect(HtmlExtractor.extract(''), isEmpty);
      expect(HtmlExtractor.extract('not html at all'), isNotEmpty);
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `cd cli && dart test test/web/fetch/html_extractor_test.dart`
Expected: FAIL — class not found

**Step 3: Implement `HtmlExtractor`**

Create `cli/lib/src/web/fetch/html_extractor.dart`:

```dart
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

/// Extracts main textual content from HTML, stripping navigation,
/// scripts, styles, and other noise. Returns cleaned HTML suitable
/// for markdown conversion.
class HtmlExtractor {
  static const _noiseTagNames = {
    'script', 'style', 'noscript', 'svg', 'canvas', 'iframe',
    'nav', 'footer', 'header', 'aside', 'form', 'button', 'input',
    'select', 'textarea', 'dialog',
  };

  /// Extract main content HTML from a full page.
  /// Returns the inner HTML of the best content candidate.
  static String extract(String html) {
    if (html.trim().isEmpty) return '';

    final doc = html_parser.parse(html);
    final body = doc.body;
    if (body == null) return _collapseWhitespace(doc.outerHtml);

    _stripNoiseTags(body);

    final candidate = _findBestCandidate(body);
    return candidate.innerHtml.trim();
  }

  static void _stripNoiseTags(Element root) {
    final toRemove = <Element>[];
    for (final element in root.querySelectorAll('*')) {
      if (_noiseTagNames.contains(element.localName?.toLowerCase())) {
        toRemove.add(element);
      }
    }
    for (final el in toRemove) {
      el.remove();
    }
  }

  static Element _findBestCandidate(Element body) {
    // Prefer semantic containers.
    for (final selector in ['article', 'main', '[role="main"]']) {
      final el = body.querySelector(selector);
      if (el != null && _textLength(el) > 100) return el;
    }

    // Score div/section candidates by text density.
    Element best = body;
    int bestScore = 0;

    for (final el in body.querySelectorAll('div, section')) {
      final score = _scoreCandidate(el);
      if (score > bestScore) {
        bestScore = score;
        best = el;
      }
    }

    return best;
  }

  static int _scoreCandidate(Element el) {
    final text = _textLength(el);
    if (text < 100) return 0;

    final paragraphs = el.querySelectorAll('p').length;
    final links = el.querySelectorAll('a').length;
    final linkDensity = text > 0 ? (links * 30) / text : 1.0;

    // Penalize high link density (navigation-heavy).
    if (linkDensity > 0.5) return 0;

    return text + (paragraphs * 50);
  }

  static int _textLength(Element el) =>
      _collapseWhitespace(el.text).length;

  static String _collapseWhitespace(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();
}
```

**Step 4: Run tests**

Run: `cd cli && dart test test/web/fetch/html_extractor_test.dart`
Expected: all pass

**Step 5: Commit**

```bash
git add cli/lib/src/web/fetch/html_extractor.dart cli/test/web/fetch/html_extractor_test.dart
git commit -m "feat(web): add HtmlExtractor for Readability-style content extraction"
```

---

### Task 5: HTML-to-Markdown converter

**Files:**
- Create: `cli/lib/src/web/fetch/html_to_markdown.dart`
- Test: `cli/test/web/fetch/html_to_markdown_test.dart`

**Step 1: Write failing tests**

Create `cli/test/web/fetch/html_to_markdown_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:glue/src/web/fetch/html_to_markdown.dart';

void main() {
  group('HtmlToMarkdown', () {
    test('converts headings', () {
      expect(HtmlToMarkdown.convert('<h1>Title</h1>'), '# Title\n\n');
      expect(HtmlToMarkdown.convert('<h2>Sub</h2>'), '## Sub\n\n');
      expect(HtmlToMarkdown.convert('<h3>H3</h3>'), '### H3\n\n');
    });

    test('converts paragraphs', () {
      expect(
        HtmlToMarkdown.convert('<p>Hello world.</p>'),
        'Hello world.\n\n',
      );
    });

    test('converts bold and italic', () {
      expect(
        HtmlToMarkdown.convert('<p><strong>bold</strong> and <em>italic</em></p>'),
        '**bold** and *italic*\n\n',
      );
    });

    test('converts links', () {
      expect(
        HtmlToMarkdown.convert('<a href="https://example.com">click</a>'),
        '[click](https://example.com)',
      );
    });

    test('converts unordered lists', () {
      final result = HtmlToMarkdown.convert(
        '<ul><li>one</li><li>two</li></ul>',
      );
      expect(result, contains('- one'));
      expect(result, contains('- two'));
    });

    test('converts ordered lists', () {
      final result = HtmlToMarkdown.convert(
        '<ol><li>first</li><li>second</li></ol>',
      );
      expect(result, contains('1. first'));
      expect(result, contains('2. second'));
    });

    test('converts code blocks', () {
      final result = HtmlToMarkdown.convert(
        '<pre><code>var x = 1;</code></pre>',
      );
      expect(result, contains('```'));
      expect(result, contains('var x = 1;'));
    });

    test('converts inline code', () {
      expect(
        HtmlToMarkdown.convert('<p>Use <code>dart run</code> to start.</p>'),
        'Use `dart run` to start.\n\n',
      );
    });

    test('converts blockquotes', () {
      final result = HtmlToMarkdown.convert(
        '<blockquote><p>A wise quote.</p></blockquote>',
      );
      expect(result, contains('> A wise quote.'));
    });

    test('converts images', () {
      expect(
        HtmlToMarkdown.convert('<img src="pic.png" alt="photo">'),
        '![photo](pic.png)',
      );
    });

    test('converts horizontal rules', () {
      expect(
        HtmlToMarkdown.convert('<hr>'),
        contains('---'),
      );
    });

    test('handles nested elements', () {
      final result = HtmlToMarkdown.convert(
        '<p>Text with <strong><em>bold italic</em></strong> end.</p>',
      );
      expect(result, contains('***bold italic***'));
    });

    test('handles empty input', () {
      expect(HtmlToMarkdown.convert(''), isEmpty);
    });

    test('strips unknown tags but keeps text', () {
      expect(
        HtmlToMarkdown.convert('<div><span>hello</span></div>'),
        contains('hello'),
      );
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `cd cli && dart test test/web/fetch/html_to_markdown_test.dart`
Expected: FAIL

**Step 3: Implement `HtmlToMarkdown`**

Create `cli/lib/src/web/fetch/html_to_markdown.dart`:

```dart
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

/// Converts HTML fragments into Markdown.
///
/// Handles common HTML elements: headings, paragraphs, lists, links,
/// images, code blocks, blockquotes, bold/italic, horizontal rules.
/// Unknown tags are stripped but their text content is preserved.
class HtmlToMarkdown {
  /// Convert an HTML string to Markdown.
  static String convert(String html) {
    if (html.trim().isEmpty) return '';

    final doc = html_parser.parseFragment(html);
    final buf = StringBuffer();
    _convertNodes(doc.nodes, buf);
    return _cleanup(buf.toString());
  }

  static void _convertNodes(List<Node> nodes, StringBuffer buf) {
    for (final node in nodes) {
      if (node is Text) {
        buf.write(_collapseWhitespace(node.text));
      } else if (node is Element) {
        _convertElement(node, buf);
      }
    }
  }

  static void _convertElement(Element el, StringBuffer buf) {
    final tag = el.localName?.toLowerCase() ?? '';

    switch (tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final level = int.parse(tag.substring(1));
        final prefix = '#' * level;
        buf.write('$prefix ');
        _convertNodes(el.nodes, buf);
        buf.write('\n\n');

      case 'p':
        _convertNodes(el.nodes, buf);
        buf.write('\n\n');

      case 'br':
        buf.write('\n');

      case 'hr':
        buf.write('\n---\n\n');

      case 'strong' || 'b':
        buf.write('**');
        _convertNodes(el.nodes, buf);
        buf.write('**');

      case 'em' || 'i':
        buf.write('*');
        _convertNodes(el.nodes, buf);
        buf.write('*');

      case 'code':
        if (_isInsidePre(el)) {
          _convertNodes(el.nodes, buf);
        } else {
          buf.write('`');
          buf.write(el.text);
          buf.write('`');
        }

      case 'pre':
        final codeEl = el.querySelector('code');
        final lang = _detectLang(codeEl);
        buf.write('\n```$lang\n');
        buf.write((codeEl ?? el).text.trim());
        buf.write('\n```\n\n');

      case 'a':
        final href = el.attributes['href'] ?? '';
        buf.write('[');
        _convertNodes(el.nodes, buf);
        buf.write(']($href)');

      case 'img':
        final src = el.attributes['src'] ?? '';
        final alt = el.attributes['alt'] ?? '';
        buf.write('![$alt]($src)');

      case 'ul':
        buf.write('\n');
        for (final li in el.children.where((c) => c.localName == 'li')) {
          buf.write('- ');
          _convertNodes(li.nodes, buf);
          buf.write('\n');
        }
        buf.write('\n');

      case 'ol':
        buf.write('\n');
        var i = 1;
        for (final li in el.children.where((c) => c.localName == 'li')) {
          buf.write('$i. ');
          _convertNodes(li.nodes, buf);
          buf.write('\n');
          i++;
        }
        buf.write('\n');

      case 'blockquote':
        final inner = StringBuffer();
        _convertNodes(el.nodes, inner);
        for (final line in inner.toString().trim().split('\n')) {
          buf.write('> $line\n');
        }
        buf.write('\n');

      case 'table':
        _convertTable(el, buf);

      default:
        _convertNodes(el.nodes, buf);
    }
  }

  static bool _isInsidePre(Element el) {
    Element? current = el.parent;
    while (current != null) {
      if (current.localName == 'pre') return true;
      current = current.parent;
    }
    return false;
  }

  static String _detectLang(Element? codeEl) {
    if (codeEl == null) return '';
    final cls = codeEl.className;
    final match = RegExp(r'language-(\w+)').firstMatch(cls);
    return match?.group(1) ?? '';
  }

  static void _convertTable(Element table, StringBuffer buf) {
    final rows = table.querySelectorAll('tr');
    if (rows.isEmpty) return;

    buf.write('\n');
    for (var r = 0; r < rows.length; r++) {
      final cells = rows[r].querySelectorAll('th, td');
      final line = cells.map((c) => c.text.trim()).join(' | ');
      buf.write('| $line |\n');
      if (r == 0) {
        buf.write('| ${cells.map((_) => '---').join(' | ')} |\n');
      }
    }
    buf.write('\n');
  }

  static String _collapseWhitespace(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ');

  static String _cleanup(String s) =>
      s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim() +
      (s.trim().isNotEmpty ? '\n' : '');
}
```

**Step 4: Run tests**

Run: `cd cli && dart test test/web/fetch/html_to_markdown_test.dart`
Expected: all pass

**Step 5: Run full analyze**

Run: `cd cli && dart analyze`
Expected: zero warnings

**Step 6: Commit**

```bash
git add cli/lib/src/web/fetch/html_to_markdown.dart cli/test/web/fetch/html_to_markdown_test.dart
git commit -m "feat(web): add HtmlToMarkdown converter with DOM-walk approach"
```

---

### Task 6: Token truncation utility

**Files:**
- Create: `cli/lib/src/web/fetch/truncation.dart`
- Test: `cli/test/web/fetch/truncation_test.dart`

**Step 1: Write failing tests**

Create `cli/test/web/fetch/truncation_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:glue/src/web/fetch/truncation.dart';

void main() {
  group('TokenTruncation', () {
    test('does not truncate short content', () {
      final result = TokenTruncation.truncate('Hello world.', maxTokens: 1000);
      expect(result, 'Hello world.');
    });

    test('truncates long content at paragraph boundary', () {
      final paragraphs = List.generate(100, (i) => 'Paragraph $i content.');
      final content = paragraphs.join('\n\n');
      final result = TokenTruncation.truncate(content, maxTokens: 50);
      expect(result.length, lessThan(content.length));
      expect(result, contains('(truncated'));
    });

    test('estimates tokens from char count', () {
      expect(TokenTruncation.estimateTokens(''), 0);
      expect(TokenTruncation.estimateTokens('four'), 1);
      expect(TokenTruncation.estimateTokens('a' * 400), 100);
    });

    test('preserves content within budget', () {
      const content = 'First paragraph.\n\nSecond paragraph.';
      final result = TokenTruncation.truncate(content, maxTokens: 100);
      expect(result, content);
    });
  });
}
```

**Step 2: Implement**

Create `cli/lib/src/web/fetch/truncation.dart`:

```dart
/// Approximate token-aware truncation for markdown content.
///
/// Uses a simple heuristic: ~4 chars per token (English).
/// Truncates at paragraph boundaries when possible.
class TokenTruncation {
  static const int _charsPerToken = 4;

  /// Estimate token count from character length.
  static int estimateTokens(String text) =>
      (text.length / _charsPerToken).ceil();

  /// Truncate [content] to approximately [maxTokens] tokens.
  /// Tries to break at paragraph boundaries (\n\n).
  static String truncate(String content, {required int maxTokens}) {
    final maxChars = maxTokens * _charsPerToken;
    if (content.length <= maxChars) return content;

    final paragraphs = content.split('\n\n');
    final buf = StringBuffer();
    var charCount = 0;

    for (final p in paragraphs) {
      if (charCount + p.length + 2 > maxChars && charCount > 0) break;
      if (charCount > 0) buf.write('\n\n');
      buf.write(p);
      charCount += p.length + 2;
    }

    final estimated = estimateTokens(buf.toString());
    buf.write('\n\n---\n(truncated to ~$estimated tokens)');
    return buf.toString();
  }
}
```

**Step 3: Run tests**

Run: `cd cli && dart test test/web/fetch/truncation_test.dart`
Expected: all pass

**Step 4: Commit**

```bash
git add cli/lib/src/web/fetch/truncation.dart cli/test/web/fetch/truncation_test.dart
git commit -m "feat(web): add TokenTruncation utility for web_fetch"
```

---

### Task 7: Jina Reader client (optional fallback)

**Files:**
- Create: `cli/lib/src/web/fetch/jina_reader_client.dart`
- Test: `cli/test/web/fetch/jina_reader_client_test.dart`

**Step 1: Write test (unit, mocking HTTP)**

Create `cli/test/web/fetch/jina_reader_client_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:glue/src/web/fetch/jina_reader_client.dart';

void main() {
  group('JinaReaderClient', () {
    test('builds correct reader URL', () {
      final client = JinaReaderClient(baseUrl: 'https://r.jina.ai');
      expect(
        client.buildReaderUrl('https://example.com/page'),
        Uri.parse('https://r.jina.ai/https://example.com/page'),
      );
    });

    test('builds correct reader URL with API key header name', () {
      final client = JinaReaderClient(
        baseUrl: 'https://r.jina.ai',
        apiKey: 'jina_test_key',
      );
      expect(client.headers, contains('Authorization'));
      expect(client.headers['Authorization'], 'Bearer jina_test_key');
    });

    test('headers omit auth when no API key', () {
      final client = JinaReaderClient(baseUrl: 'https://r.jina.ai');
      expect(client.headers, isNot(contains('Authorization')));
    });
  });
}
```

**Step 2: Implement**

Create `cli/lib/src/web/fetch/jina_reader_client.dart`:

```dart
import 'dart:async';
import 'package:http/http.dart' as http;

/// Client for Jina Reader API (r.jina.ai).
/// Converts URLs to LLM-friendly markdown via Jina's service.
class JinaReaderClient {
  final String baseUrl;
  final String? apiKey;
  final int timeoutSeconds;

  JinaReaderClient({
    this.baseUrl = 'https://r.jina.ai',
    this.apiKey,
    this.timeoutSeconds = 30,
  });

  Uri buildReaderUrl(String targetUrl) =>
      Uri.parse('$baseUrl/$targetUrl');

  Map<String, String> get headers {
    final h = <String, String>{
      'Accept': 'text/markdown',
    };
    if (apiKey != null && apiKey!.isNotEmpty) {
      h['Authorization'] = 'Bearer $apiKey';
    }
    return h;
  }

  /// Fetch [url] via Jina Reader and return markdown content.
  /// Returns null on failure (non-200, timeout, etc.).
  Future<String?> fetch(String url) async {
    try {
      final response = await http
          .get(buildReaderUrl(url), headers: headers)
          .timeout(Duration(seconds: timeoutSeconds));

      if (response.statusCode == 200) {
        return response.body;
      }
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
```

**Step 3: Run tests**

Run: `cd cli && dart test test/web/fetch/jina_reader_client_test.dart`
Expected: all pass

**Step 4: Commit**

```bash
git add cli/lib/src/web/fetch/jina_reader_client.dart cli/test/web/fetch/jina_reader_client_test.dart
git commit -m "feat(web): add JinaReaderClient for optional fetch fallback"
```

---

### Task 8: `WebFetchClient` (pipeline orchestrator)

**Files:**
- Create: `cli/lib/src/web/fetch/web_fetch_client.dart`
- Test: `cli/test/web/fetch/web_fetch_client_test.dart`

**Step 1: Write failing tests**

Create `cli/test/web/fetch/web_fetch_client_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:glue/src/web/fetch/web_fetch_client.dart';
import 'package:glue/src/web/web_config.dart';

void main() {
  group('WebFetchClient', () {
    late WebFetchClient client;

    setUp(() {
      client = WebFetchClient(
        config: const WebFetchConfig(allowJinaFallback: false),
      );
    });

    test('rejects invalid URLs', () async {
      final result = await client.fetch('not-a-url');
      expect(result.error, isNotNull);
      expect(result.error, contains('Invalid URL'));
    });

    test('rejects non-http schemes', () async {
      final result = await client.fetch('ftp://files.example.com/doc');
      expect(result.error, isNotNull);
    });

    test('result model has expected fields', () {
      final result = WebFetchResult(
        url: 'https://example.com',
        markdown: '# Hello',
        title: 'Example',
      );
      expect(result.url, 'https://example.com');
      expect(result.markdown, '# Hello');
      expect(result.title, 'Example');
      expect(result.error, isNull);
    });

    test('error result', () {
      final result = WebFetchResult.withError(
        url: 'https://bad.com',
        error: 'Connection failed',
      );
      expect(result.markdown, isNull);
      expect(result.error, 'Connection failed');
    });
  });
}
```

**Step 2: Implement**

Create `cli/lib/src/web/fetch/web_fetch_client.dart`:

```dart
import 'dart:async';
import 'package:http/http.dart' as http;
import '../web_config.dart';
import 'html_extractor.dart';
import 'html_to_markdown.dart';
import 'jina_reader_client.dart';
import 'truncation.dart';

/// Result from a web fetch operation.
class WebFetchResult {
  final String url;
  final String? markdown;
  final String? title;
  final String? error;
  final int? estimatedTokens;

  WebFetchResult({
    required this.url,
    this.markdown,
    this.title,
    this.error,
    this.estimatedTokens,
  });

  factory WebFetchResult.withError({
    required String url,
    required String error,
  }) =>
      WebFetchResult(url: url, error: error);

  bool get isSuccess => markdown != null && error == null;
}

/// Orchestrates the web_fetch pipeline:
/// 1. Try Accept: text/markdown (Cloudflare convention)
/// 2. HTTP GET → HTML extract → convert to markdown
/// 3. Optional Jina Reader fallback
class WebFetchClient {
  final WebFetchConfig config;
  late final JinaReaderClient? _jinaClient;

  WebFetchClient({required this.config}) {
    _jinaClient = config.allowJinaFallback
        ? JinaReaderClient(
            baseUrl: config.jinaBaseUrl,
            apiKey: config.jinaApiKey,
            timeoutSeconds: config.timeoutSeconds,
          )
        : null;
  }

  Future<WebFetchResult> fetch(String url, {int? maxTokens}) async {
    final budget = maxTokens ?? config.defaultMaxTokens;

    // Validate URL.
    final Uri uri;
    try {
      uri = Uri.parse(url);
      if (!uri.hasScheme || !{'http', 'https'}.contains(uri.scheme)) {
        return WebFetchResult.withError(
          url: url,
          error: 'Invalid URL: must use http or https scheme',
        );
      }
      if (uri.host.isEmpty) {
        return WebFetchResult.withError(
          url: url,
          error: 'Invalid URL: missing host',
        );
      }
    } catch (e) {
      return WebFetchResult.withError(url: url, error: 'Invalid URL: $e');
    }

    // Stage 1: Try Accept: text/markdown.
    try {
      final mdResult = await _tryMarkdownFetch(uri);
      if (mdResult != null) {
        final truncated = TokenTruncation.truncate(mdResult, maxTokens: budget);
        return WebFetchResult(
          url: url,
          markdown: truncated,
          estimatedTokens: TokenTruncation.estimateTokens(truncated),
        );
      }
    } catch (_) {}

    // Stage 2: HTML fetch → extract → convert.
    try {
      final htmlResult = await _htmlFetchAndConvert(uri, budget);
      if (htmlResult != null && htmlResult.isSuccess) return htmlResult;
    } catch (_) {}

    // Stage 3: Jina Reader fallback.
    if (_jinaClient != null) {
      try {
        final jinaResult = await _jinaClient!.fetch(url);
        if (jinaResult != null && jinaResult.trim().isNotEmpty) {
          final truncated =
              TokenTruncation.truncate(jinaResult, maxTokens: budget);
          return WebFetchResult(
            url: url,
            markdown: truncated,
            estimatedTokens: TokenTruncation.estimateTokens(truncated),
          );
        }
      } catch (_) {}
    }

    return WebFetchResult.withError(
      url: url,
      error: 'Failed to fetch content from $url',
    );
  }

  Future<String?> _tryMarkdownFetch(Uri uri) async {
    final response = await http
        .get(uri, headers: {
          'Accept': 'text/markdown, text/plain;q=0.9, text/html;q=0.8',
          'User-Agent': 'Glue/0.1 (coding-agent)',
        })
        .timeout(Duration(seconds: config.timeoutSeconds));

    if (response.statusCode != 200) return null;

    final contentType = response.headers['content-type'] ?? '';
    if (contentType.contains('text/markdown')) {
      return response.body;
    }

    return null;
  }

  Future<WebFetchResult?> _htmlFetchAndConvert(Uri uri, int maxTokens) async {
    final response = await http
        .get(uri, headers: {
          'Accept': 'text/html, */*;q=0.1',
          'User-Agent': 'Glue/0.1 (coding-agent)',
        })
        .timeout(Duration(seconds: config.timeoutSeconds));

    if (response.statusCode != 200) return null;

    final contentType = response.headers['content-type'] ?? '';

    // Reject binary content.
    if (!contentType.contains('text/') && !contentType.contains('html')) {
      return null;
    }

    // Enforce byte limit.
    if (response.bodyBytes.length > config.maxBytes) {
      return WebFetchResult.withError(
        url: uri.toString(),
        error: 'Response too large: ${response.bodyBytes.length} bytes '
            '(max ${config.maxBytes})',
      );
    }

    final extractedHtml = HtmlExtractor.extract(response.body);
    final markdown = HtmlToMarkdown.convert(extractedHtml);

    if (markdown.trim().isEmpty) return null;

    // Extract title.
    final titleMatch =
        RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false)
            .firstMatch(response.body);
    final title = titleMatch?.group(1)?.trim();

    final truncated = TokenTruncation.truncate(markdown, maxTokens: maxTokens);

    return WebFetchResult(
      url: uri.toString(),
      markdown: truncated,
      title: title,
      estimatedTokens: TokenTruncation.estimateTokens(truncated),
    );
  }
}
```

**Step 3: Run tests**

Run: `cd cli && dart test test/web/fetch/web_fetch_client_test.dart`
Expected: all pass

**Step 4: Commit**

```bash
git add cli/lib/src/web/fetch/web_fetch_client.dart cli/test/web/fetch/web_fetch_client_test.dart
git commit -m "feat(web): add WebFetchClient pipeline orchestrator"
```

---

### Task 9: `WebFetchTool` (Tool wrapper)

**Files:**
- Create: `cli/lib/src/tools/web_fetch_tool.dart`
- Test: `cli/test/tools/web_fetch_tool_test.dart`

**Step 1: Write failing test**

Create `cli/test/tools/web_fetch_tool_test.dart`:

```dart
import 'package:test/test.dart';
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
      final result = await tool.execute({});
      expect(result, contains('Error'));
    });

    test('returns error for invalid url', () async {
      final result = await tool.execute({'url': 'not-a-url'});
      expect(result, contains('Invalid URL'));
    });

    test('schema has correct structure', () {
      final schema = tool.toSchema();
      expect(schema['name'], 'web_fetch');
      expect(schema['input_schema']['properties'], contains('url'));
    });
  });
}
```

**Step 2: Implement**

Create `cli/lib/src/tools/web_fetch_tool.dart`:

```dart
import '../agent/tools.dart';
import '../web/web_config.dart';
import '../web/fetch/web_fetch_client.dart';

/// Tool: fetch a URL and return its content as LLM-friendly markdown.
///
/// Pipeline: (1) Accept: text/markdown, (2) HTML extract + convert,
/// (3) optional Jina Reader fallback.
class WebFetchTool extends Tool {
  final WebFetchClient _client;

  WebFetchTool(WebFetchConfig config)
      : _client = WebFetchClient(config: config);

  @override
  String get name => 'web_fetch';

  @override
  String get description =>
      'Fetch the content of a web page at the given URL and return it as '
      'clean markdown. Handles static HTML pages. Does not execute JavaScript.';

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'url',
          type: 'string',
          description: 'The URL to fetch (must be http or https).',
        ),
        ToolParameter(
          name: 'max_tokens',
          type: 'integer',
          description: 'Maximum approximate token budget for the response.',
          required: false,
        ),
      ];

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final url = args['url'];
    if (url is! String || url.isEmpty) return 'Error: no URL provided';

    final maxTokens = args['max_tokens'] as int?;
    final result = await _client.fetch(url, maxTokens: maxTokens);

    if (!result.isSuccess) {
      return 'Error: ${result.error}';
    }

    final buf = StringBuffer();
    if (result.title != null) {
      buf.writeln('# ${result.title}');
      buf.writeln('Source: ${result.url}');
      buf.writeln();
    }
    buf.write(result.markdown!);
    return buf.toString();
  }
}
```

**Step 3: Run tests**

Run: `cd cli && dart test test/tools/web_fetch_tool_test.dart`
Expected: all pass

**Step 4: Commit**

```bash
git add cli/lib/src/tools/web_fetch_tool.dart cli/test/tools/web_fetch_tool_test.dart
git commit -m "feat(tools): add web_fetch tool"
```

---

## Phase 3: `web_search` Tool

### Task 10: Unified search models + provider interface

**Files:**
- Create: `cli/lib/src/web/search/models.dart`
- Create: `cli/lib/src/web/search/provider.dart`
- Test: `cli/test/web/search/models_test.dart`

**Step 1: Write failing tests**

Create `cli/test/web/search/models_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:glue/src/web/search/models.dart';

void main() {
  group('WebSearchResult', () {
    test('creates with all fields', () {
      final result = WebSearchResult(
        title: 'Test',
        url: Uri.parse('https://example.com'),
        snippet: 'A snippet',
      );
      expect(result.title, 'Test');
      expect(result.url.host, 'example.com');
      expect(result.snippet, 'A snippet');
    });

    test('formats as readable text', () {
      final result = WebSearchResult(
        title: 'Page Title',
        url: Uri.parse('https://example.com/page'),
        snippet: 'Description of the page.',
      );
      final text = result.toText();
      expect(text, contains('Page Title'));
      expect(text, contains('https://example.com/page'));
      expect(text, contains('Description'));
    });
  });

  group('WebSearchResponse', () {
    test('formats results as text', () {
      final response = WebSearchResponse(
        provider: 'brave',
        query: 'test query',
        results: [
          WebSearchResult(
            title: 'Result 1',
            url: Uri.parse('https://r1.com'),
            snippet: 'First result.',
          ),
          WebSearchResult(
            title: 'Result 2',
            url: Uri.parse('https://r2.com'),
            snippet: 'Second result.',
          ),
        ],
      );
      final text = response.toText();
      expect(text, contains('Result 1'));
      expect(text, contains('Result 2'));
      expect(text, contains('brave'));
    });

    test('empty results produce clear message', () {
      final response = WebSearchResponse(
        provider: 'brave',
        query: 'nothing',
        results: [],
      );
      expect(response.toText(), contains('No results'));
    });
  });
}
```

**Step 2: Implement models**

Create `cli/lib/src/web/search/models.dart`:

```dart
/// A single web search result.
class WebSearchResult {
  final String title;
  final Uri url;
  final String snippet;
  final DateTime? publishedAt;

  const WebSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
    this.publishedAt,
  });

  String toText() {
    final buf = StringBuffer();
    buf.writeln('**$title**');
    buf.writeln(url);
    buf.writeln(snippet);
    if (publishedAt != null) {
      buf.writeln('Published: ${publishedAt!.toIso8601String().split('T').first}');
    }
    return buf.toString();
  }
}

/// Response from a web search operation.
class WebSearchResponse {
  final String provider;
  final String query;
  final List<WebSearchResult> results;
  final String? aiSummary;

  const WebSearchResponse({
    required this.provider,
    required this.query,
    required this.results,
    this.aiSummary,
  });

  String toText() {
    if (results.isEmpty) return 'No results found for "$query" (via $provider).';

    final buf = StringBuffer();
    buf.writeln('Search results for "$query" (via $provider):');
    buf.writeln();
    if (aiSummary != null) {
      buf.writeln(aiSummary);
      buf.writeln();
    }
    for (var i = 0; i < results.length; i++) {
      buf.writeln('${i + 1}. ${results[i].toText()}');
    }
    return buf.toString().trim();
  }
}
```

**Step 3: Create provider interface**

Create `cli/lib/src/web/search/provider.dart`:

```dart
import 'models.dart';

/// Interface for web search providers.
///
/// Implementations translate a query into provider-specific HTTP calls
/// and map responses into the unified [WebSearchResponse] model.
abstract class WebSearchProvider {
  /// Provider name (e.g. 'brave', 'tavily').
  String get name;

  /// Whether this provider has valid configuration (API key, etc.).
  bool get isConfigured;

  /// Execute a search query and return unified results.
  Future<WebSearchResponse> search(
    String query, {
    int maxResults = 5,
  });
}
```

**Step 4: Run tests**

Run: `cd cli && dart test test/web/search/models_test.dart`
Expected: all pass

**Step 5: Commit**

```bash
git add cli/lib/src/web/search/models.dart cli/lib/src/web/search/provider.dart cli/test/web/search/models_test.dart
git commit -m "feat(web): add unified WebSearchResult/Response models and provider interface"
```

---

### Task 11: Brave Search provider

**Files:**
- Create: `cli/lib/src/web/search/providers/brave_provider.dart`
- Test: `cli/test/web/search/providers/brave_provider_test.dart`

**Step 1: Write failing tests**

Create `cli/test/web/search/providers/brave_provider_test.dart`:

```dart
import 'dart:convert';
import 'package:test/test.dart';
import 'package:glue/src/web/search/providers/brave_provider.dart';

void main() {
  group('BraveSearchProvider', () {
    test('isConfigured returns false without API key', () {
      final provider = BraveSearchProvider(apiKey: null);
      expect(provider.isConfigured, isFalse);
    });

    test('isConfigured returns true with API key', () {
      final provider = BraveSearchProvider(apiKey: 'test-key');
      expect(provider.isConfigured, isTrue);
    });

    test('name is brave', () {
      final provider = BraveSearchProvider(apiKey: 'key');
      expect(provider.name, 'brave');
    });

    test('parseResponse handles valid JSON', () {
      final json = jsonDecode('''{
        "web": {
          "results": [
            {
              "title": "Test Page",
              "url": "https://example.com",
              "description": "A test page description."
            },
            {
              "title": "Another Page",
              "url": "https://example.org",
              "description": "Another description."
            }
          ]
        }
      }''') as Map<String, dynamic>;

      final results = BraveSearchProvider.parseResponse(json, 'test');
      expect(results.results, hasLength(2));
      expect(results.results[0].title, 'Test Page');
      expect(results.results[0].url.host, 'example.com');
      expect(results.results[1].snippet, 'Another description.');
      expect(results.provider, 'brave');
    });

    test('parseResponse handles empty results', () {
      final json = <String, dynamic>{
        'web': {'results': <dynamic>[]},
      };
      final results = BraveSearchProvider.parseResponse(json, 'test');
      expect(results.results, isEmpty);
    });

    test('parseResponse handles missing web key', () {
      final results = BraveSearchProvider.parseResponse({}, 'test');
      expect(results.results, isEmpty);
    });
  });
}
```

**Step 2: Implement**

Create `cli/lib/src/web/search/providers/brave_provider.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';
import '../provider.dart';

/// Brave Search API provider.
///
/// API docs: https://api.search.brave.com/app/documentation/web-search
class BraveSearchProvider implements WebSearchProvider {
  final String? apiKey;
  final int timeoutSeconds;
  static const _baseUrl = 'https://api.search.brave.com/res/v1/web/search';

  BraveSearchProvider({
    required this.apiKey,
    this.timeoutSeconds = 15,
  });

  @override
  String get name => 'brave';

  @override
  bool get isConfigured => apiKey != null && apiKey!.isNotEmpty;

  @override
  Future<WebSearchResponse> search(
    String query, {
    int maxResults = 5,
  }) async {
    if (!isConfigured) {
      throw StateError('Brave Search API key not configured');
    }

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'q': query,
      'count': maxResults.toString(),
    });

    final response = await http
        .get(uri, headers: {
          'Accept': 'application/json',
          'Accept-Encoding': 'gzip',
          'X-Subscription-Token': apiKey!,
        })
        .timeout(Duration(seconds: timeoutSeconds));

    if (response.statusCode != 200) {
      throw HttpException(
        'Brave Search API returned ${response.statusCode}: '
        '${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return parseResponse(json, query);
  }

  static WebSearchResponse parseResponse(
    Map<String, dynamic> json,
    String query,
  ) {
    final web = json['web'] as Map<String, dynamic>?;
    final rawResults = (web?['results'] as List<dynamic>?) ?? [];

    final results = rawResults.map((r) {
      final item = r as Map<String, dynamic>;
      return WebSearchResult(
        title: item['title'] as String? ?? '',
        url: Uri.parse(item['url'] as String? ?? ''),
        snippet: item['description'] as String? ?? '',
      );
    }).toList();

    return WebSearchResponse(
      provider: 'brave',
      query: query,
      results: results,
    );
  }
}

class HttpException implements Exception {
  final String message;
  HttpException(this.message);
  @override
  String toString() => 'HttpException: $message';
}
```

**Step 3: Run tests**

Run: `cd cli && dart test test/web/search/providers/brave_provider_test.dart`
Expected: all pass

**Step 4: Commit**

```bash
git add cli/lib/src/web/search/providers/brave_provider.dart cli/test/web/search/providers/brave_provider_test.dart
git commit -m "feat(web): add Brave Search provider"
```

---

### Task 12: Tavily Search provider

**Files:**
- Create: `cli/lib/src/web/search/providers/tavily_provider.dart`
- Test: `cli/test/web/search/providers/tavily_provider_test.dart`

**Step 1: Write failing tests**

Create `cli/test/web/search/providers/tavily_provider_test.dart`:

```dart
import 'dart:convert';
import 'package:test/test.dart';
import 'package:glue/src/web/search/providers/tavily_provider.dart';

void main() {
  group('TavilySearchProvider', () {
    test('isConfigured returns false without API key', () {
      final provider = TavilySearchProvider(apiKey: null);
      expect(provider.isConfigured, isFalse);
    });

    test('isConfigured returns true with API key', () {
      final provider = TavilySearchProvider(apiKey: 'tvly-key');
      expect(provider.isConfigured, isTrue);
    });

    test('name is tavily', () {
      final provider = TavilySearchProvider(apiKey: 'key');
      expect(provider.name, 'tavily');
    });

    test('parseResponse handles valid JSON', () {
      final json = jsonDecode('''{
        "query": "test",
        "results": [
          {
            "title": "Tavily Result",
            "url": "https://example.com/tavily",
            "content": "Detailed content from Tavily."
          }
        ],
        "answer": "AI-generated summary."
      }''') as Map<String, dynamic>;

      final results = TavilySearchProvider.parseResponse(json);
      expect(results.results, hasLength(1));
      expect(results.results[0].title, 'Tavily Result');
      expect(results.aiSummary, 'AI-generated summary.');
      expect(results.provider, 'tavily');
    });

    test('parseResponse handles missing answer', () {
      final json = <String, dynamic>{
        'query': 'test',
        'results': <dynamic>[],
      };
      final results = TavilySearchProvider.parseResponse(json);
      expect(results.aiSummary, isNull);
    });
  });
}
```

**Step 2: Implement**

Create `cli/lib/src/web/search/providers/tavily_provider.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';
import '../provider.dart';

/// Tavily Search API provider.
///
/// API docs: https://docs.tavily.com
class TavilySearchProvider implements WebSearchProvider {
  final String? apiKey;
  final int timeoutSeconds;
  static const _baseUrl = 'https://api.tavily.com/search';

  TavilySearchProvider({
    required this.apiKey,
    this.timeoutSeconds = 15,
  });

  @override
  String get name => 'tavily';

  @override
  bool get isConfigured => apiKey != null && apiKey!.isNotEmpty;

  @override
  Future<WebSearchResponse> search(
    String query, {
    int maxResults = 5,
  }) async {
    if (!isConfigured) {
      throw StateError('Tavily API key not configured');
    }

    final response = await http
        .post(
          Uri.parse(_baseUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'query': query,
            'max_results': maxResults,
            'include_answer': true,
          }),
        )
        .timeout(Duration(seconds: timeoutSeconds));

    if (response.statusCode != 200) {
      throw Exception(
        'Tavily API returned ${response.statusCode}: '
        '${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return parseResponse(json);
  }

  static WebSearchResponse parseResponse(Map<String, dynamic> json) {
    final rawResults = (json['results'] as List<dynamic>?) ?? [];

    final results = rawResults.map((r) {
      final item = r as Map<String, dynamic>;
      return WebSearchResult(
        title: item['title'] as String? ?? '',
        url: Uri.parse(item['url'] as String? ?? ''),
        snippet: item['content'] as String? ?? '',
      );
    }).toList();

    return WebSearchResponse(
      provider: 'tavily',
      query: json['query'] as String? ?? '',
      results: results,
      aiSummary: json['answer'] as String?,
    );
  }
}
```

**Step 3: Run tests**

Run: `cd cli && dart test test/web/search/providers/tavily_provider_test.dart`
Expected: all pass

**Step 4: Commit**

```bash
git add cli/lib/src/web/search/providers/tavily_provider.dart cli/test/web/search/providers/tavily_provider_test.dart
git commit -m "feat(web): add Tavily Search provider"
```

---

### Task 13: Firecrawl Search provider

**Files:**
- Create: `cli/lib/src/web/search/providers/firecrawl_provider.dart`
- Test: `cli/test/web/search/providers/firecrawl_provider_test.dart`

**Step 1: Write failing tests**

Create `cli/test/web/search/providers/firecrawl_provider_test.dart`:

```dart
import 'dart:convert';
import 'package:test/test.dart';
import 'package:glue/src/web/search/providers/firecrawl_provider.dart';

void main() {
  group('FirecrawlSearchProvider', () {
    test('isConfigured returns false without API key', () {
      final provider = FirecrawlSearchProvider(apiKey: null);
      expect(provider.isConfigured, isFalse);
    });

    test('isConfigured returns true with API key', () {
      final provider = FirecrawlSearchProvider(apiKey: 'fc-key');
      expect(provider.isConfigured, isTrue);
    });

    test('name is firecrawl', () {
      final provider = FirecrawlSearchProvider(apiKey: 'key');
      expect(provider.name, 'firecrawl');
    });

    test('parseResponse handles valid JSON', () {
      final json = jsonDecode('''{
        "success": true,
        "data": [
          {
            "title": "Firecrawl Result",
            "url": "https://example.com/fc",
            "description": "Content from Firecrawl.",
            "markdown": "# Full Content"
          }
        ]
      }''') as Map<String, dynamic>;

      final results = FirecrawlSearchProvider.parseResponse(json, 'test');
      expect(results.results, hasLength(1));
      expect(results.results[0].title, 'Firecrawl Result');
      expect(results.provider, 'firecrawl');
    });

    test('parseResponse handles empty data', () {
      final json = <String, dynamic>{
        'success': true,
        'data': <dynamic>[],
      };
      final results = FirecrawlSearchProvider.parseResponse(json, 'test');
      expect(results.results, isEmpty);
    });
  });
}
```

**Step 2: Implement**

Create `cli/lib/src/web/search/providers/firecrawl_provider.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';
import '../provider.dart';

/// Firecrawl Search API provider.
///
/// API docs: https://docs.firecrawl.dev
class FirecrawlSearchProvider implements WebSearchProvider {
  final String? apiKey;
  final String baseUrl;
  final int timeoutSeconds;

  FirecrawlSearchProvider({
    required this.apiKey,
    this.baseUrl = 'https://api.firecrawl.dev',
    this.timeoutSeconds = 15,
  });

  @override
  String get name => 'firecrawl';

  @override
  bool get isConfigured => apiKey != null && apiKey!.isNotEmpty;

  @override
  Future<WebSearchResponse> search(
    String query, {
    int maxResults = 5,
  }) async {
    if (!isConfigured) {
      throw StateError('Firecrawl API key not configured');
    }

    final response = await http
        .post(
          Uri.parse('$baseUrl/v1/search'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'query': query,
            'limit': maxResults,
          }),
        )
        .timeout(Duration(seconds: timeoutSeconds));

    if (response.statusCode != 200) {
      throw Exception(
        'Firecrawl API returned ${response.statusCode}: '
        '${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return parseResponse(json, query);
  }

  static WebSearchResponse parseResponse(
    Map<String, dynamic> json,
    String query,
  ) {
    final rawResults = (json['data'] as List<dynamic>?) ?? [];

    final results = rawResults.map((r) {
      final item = r as Map<String, dynamic>;
      return WebSearchResult(
        title: item['title'] as String? ?? '',
        url: Uri.parse(item['url'] as String? ?? ''),
        snippet: item['description'] as String? ??
            item['markdown'] as String? ??
            '',
      );
    }).toList();

    return WebSearchResponse(
      provider: 'firecrawl',
      query: query,
      results: results,
    );
  }
}
```

**Step 3: Run tests**

Run: `cd cli && dart test test/web/search/providers/firecrawl_provider_test.dart`
Expected: all pass

**Step 4: Commit**

```bash
git add cli/lib/src/web/search/providers/firecrawl_provider.dart cli/test/web/search/providers/firecrawl_provider_test.dart
git commit -m "feat(web): add Firecrawl Search provider"
```

---

### Task 14: Search router (auto-detect + fallback)

**Files:**
- Create: `cli/lib/src/web/search/search_router.dart`
- Test: `cli/test/web/search/search_router_test.dart`

**Step 1: Write failing tests**

Create `cli/test/web/search/search_router_test.dart`:

```dart
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
```

**Step 2: Implement**

Create `cli/lib/src/web/search/search_router.dart`:

```dart
import 'models.dart';
import 'provider.dart';

/// Routes search queries to the appropriate provider with fallback.
///
/// Provider priority is determined by list order. Auto-detects the
/// first configured provider. Falls back to the next on error.
class SearchRouter {
  final List<WebSearchProvider> providers;

  SearchRouter(this.providers);

  /// The first configured provider, or null if none available.
  WebSearchProvider? get defaultProvider {
    for (final p in providers) {
      if (p.isConfigured) return p;
    }
    return null;
  }

  /// Search using the specified or default provider, with fallback.
  Future<WebSearchResponse> search(
    String query, {
    int maxResults = 5,
    String? providerName,
    bool fallback = true,
  }) async {
    if (providerName != null) {
      final provider = providers.firstWhere(
        (p) => p.name == providerName && p.isConfigured,
        orElse: () => throw StateError(
          'Search provider "$providerName" not found or not configured',
        ),
      );
      return provider.search(query, maxResults: maxResults);
    }

    final configured = providers.where((p) => p.isConfigured).toList();
    if (configured.isEmpty) {
      throw StateError(
        'No search provider configured. Set one of: '
        'BRAVE_API_KEY, TAVILY_API_KEY, or FIRECRAWL_API_KEY',
      );
    }

    Exception? lastError;
    for (final provider in configured) {
      try {
        return await provider.search(query, maxResults: maxResults);
      } catch (e) {
        lastError = e is Exception ? e : Exception('$e');
        if (!fallback) rethrow;
      }
    }

    throw lastError!;
  }
}
```

**Step 3: Run tests**

Run: `cd cli && dart test test/web/search/search_router_test.dart`
Expected: all pass

**Step 4: Commit**

```bash
git add cli/lib/src/web/search/search_router.dart cli/test/web/search/search_router_test.dart
git commit -m "feat(web): add SearchRouter with auto-detect and fallback"
```

---

### Task 15: `WebSearchTool` (Tool wrapper)

**Files:**
- Create: `cli/lib/src/tools/web_search_tool.dart`
- Test: `cli/test/tools/web_search_tool_test.dart`

**Step 1: Write failing test**

Create `cli/test/tools/web_search_tool_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:glue/src/tools/web_search_tool.dart';
import 'package:glue/src/web/search/search_router.dart';
import 'package:glue/src/web/search/models.dart';
import 'package:glue/src/web/search/provider.dart';

class _MockProvider implements WebSearchProvider {
  @override
  String get name => 'mock';
  @override
  bool get isConfigured => true;

  @override
  Future<WebSearchResponse> search(String query, {int maxResults = 5}) async {
    return WebSearchResponse(
      provider: 'mock',
      query: query,
      results: [
        WebSearchResult(
          title: 'Mock Result',
          url: Uri.parse('https://mock.com'),
          snippet: 'Mock snippet.',
        ),
      ],
    );
  }
}

void main() {
  group('WebSearchTool', () {
    late WebSearchTool tool;

    setUp(() {
      tool = WebSearchTool(SearchRouter([_MockProvider()]));
    });

    test('has correct name', () {
      expect(tool.name, 'web_search');
    });

    test('has query parameter', () {
      expect(tool.parameters.any((p) => p.name == 'query'), isTrue);
    });

    test('returns error for missing query', () async {
      final result = await tool.execute({});
      expect(result, contains('Error'));
    });

    test('returns formatted results', () async {
      final result = await tool.execute({'query': 'test search'});
      expect(result, contains('Mock Result'));
      expect(result, contains('mock.com'));
    });

    test('schema has correct structure', () {
      final schema = tool.toSchema();
      expect(schema['name'], 'web_search');
      expect(schema['input_schema']['properties'], contains('query'));
    });
  });
}
```

**Step 2: Implement**

Create `cli/lib/src/tools/web_search_tool.dart`:

```dart
import '../agent/tools.dart';
import '../web/search/search_router.dart';

/// Tool: search the web and return structured results.
///
/// Uses a configurable search provider (Brave, Tavily, Firecrawl)
/// with automatic fallback on failure.
class WebSearchTool extends Tool {
  final SearchRouter _router;

  WebSearchTool(this._router);

  @override
  String get name => 'web_search';

  @override
  String get description =>
      'Search the web for information. Returns titles, URLs, and '
      'snippets from search results. Use web_fetch to read full '
      'content from a specific URL found in search results.';

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'query',
          type: 'string',
          description: 'The search query.',
        ),
        ToolParameter(
          name: 'max_results',
          type: 'integer',
          description: 'Maximum number of results to return (default: 5).',
          required: false,
        ),
        ToolParameter(
          name: 'provider',
          type: 'string',
          description:
              'Search provider to use: "brave", "tavily", or "firecrawl". '
              'Defaults to auto-detect from configured API keys.',
          required: false,
        ),
      ];

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final query = args['query'];
    if (query is! String || query.isEmpty) return 'Error: no query provided';

    final maxResults = (args['max_results'] as num?)?.toInt() ?? 5;
    final providerName = args['provider'] as String?;

    try {
      final response = await _router.search(
        query,
        maxResults: maxResults,
        providerName: providerName,
      );
      return response.toText();
    } catch (e) {
      return 'Error: $e';
    }
  }
}
```

**Step 3: Run tests**

Run: `cd cli && dart test test/tools/web_search_tool_test.dart`
Expected: all pass

**Step 4: Commit**

```bash
git add cli/lib/src/tools/web_search_tool.dart cli/test/tools/web_search_tool_test.dart
git commit -m "feat(tools): add web_search tool"
```

---

## Phase 4: Integration

### Task 16: Register web tools in tool registry

**Files:**
- Modify: wherever tools are registered (likely `cli/lib/src/app.dart` or `cli/lib/src/agent/tools.dart`)

**Step 1: Find where tools are registered**

Search for where the tool map is built — look for `ReadFileTool()`, `WriteFileTool()`, etc. in app.dart or main entry point.

**Step 2: Add web tools**

Import the new tools and add them to the tool registry:

```dart
import 'tools/web_fetch_tool.dart';
import 'tools/web_search_tool.dart';
import 'web/search/search_router.dart';
import 'web/search/providers/brave_provider.dart';
import 'web/search/providers/tavily_provider.dart';
import 'web/search/providers/firecrawl_provider.dart';
```

Build and register the tools:

```dart
// Build search router from config.
final searchRouter = SearchRouter([
  BraveSearchProvider(apiKey: config.webConfig.search.braveApiKey),
  TavilySearchProvider(apiKey: config.webConfig.search.tavilyApiKey),
  FirecrawlSearchProvider(
    apiKey: config.webConfig.search.firecrawlApiKey,
    baseUrl: config.webConfig.search.firecrawlBaseUrl ?? 'https://api.firecrawl.dev',
  ),
]);

// Add to tools map:
'web_fetch': WebFetchTool(config.webConfig.fetch),
'web_search': WebSearchTool(searchRouter),
```

**Step 3: Run full test suite**

Run: `cd cli && dart analyze && dart test`
Expected: zero warnings, all tests pass

**Step 4: Commit**

```bash
git add -A  # only changed files
git commit -m "feat: register web_fetch and web_search tools in agent"
```

---

### Task 17: Full integration test

Run: `cd cli && dart analyze && dart test`
Expected: zero warnings, all 452+ existing tests pass, plus ~50 new web tests pass.

Verify tool schemas look correct:
```bash
cd cli && dart run bin/glue.dart --help
```

**Commit:**

```bash
git commit -m "chore: verify full test suite with web tools"
```

---

## Phase 5 (Future): PDF Support + Browser Tool

### Task 18 (Future): PDF extraction via Docker

Add PDF content-type detection in `WebFetchClient`. When a URL returns `application/pdf`, download to temp file and extract text via `pdftotext` (poppler-utils). Use `DockerExecutor` if Docker is configured, otherwise try host `pdftotext`.

### Task 19 (Future): Web browser tool

Implement `WebBrowserTool` using Playwright in a Docker container. Provide swappable backends for local Playwright, Steel.dev, and Browserbase via CDP WebSocket. Actions: navigate, screenshot, click, extract, evaluate.

---

## File Tree Summary

```
cli/lib/src/
├── web/
│   ├── web_config.dart           # Task 2
│   ├── fetch/
│   │   ├── html_extractor.dart    # Task 4
│   │   ├── html_to_markdown.dart  # Task 5
│   │   ├── truncation.dart        # Task 6
│   │   ├── jina_reader_client.dart # Task 7
│   │   └── web_fetch_client.dart  # Task 8
│   └── search/
│       ├── models.dart            # Task 10
│       ├── provider.dart          # Task 10
│       ├── search_router.dart     # Task 14
│       └── providers/
│           ├── brave_provider.dart    # Task 11
│           ├── tavily_provider.dart   # Task 12
│           └── firecrawl_provider.dart # Task 13
├── tools/
│   ├── web_fetch_tool.dart        # Task 9
│   └── web_search_tool.dart       # Task 15
└── config/
    ├── constants.dart             # Task 2 (modified)
    └── glue_config.dart           # Task 3 (modified)

cli/test/
├── web/
│   ├── web_config_test.dart       # Task 2
│   ├── fetch/
│   │   ├── html_extractor_test.dart     # Task 4
│   │   ├── html_to_markdown_test.dart   # Task 5
│   │   ├── truncation_test.dart         # Task 6
│   │   ├── jina_reader_client_test.dart # Task 7
│   │   └── web_fetch_client_test.dart   # Task 8
│   └── search/
│       ├── models_test.dart             # Task 10
│       ├── search_router_test.dart      # Task 14
│       └── providers/
│           ├── brave_provider_test.dart     # Task 11
│           ├── tavily_provider_test.dart    # Task 12
│           └── firecrawl_provider_test.dart # Task 13
└── tools/
    ├── web_fetch_tool_test.dart    # Task 9
    └── web_search_tool_test.dart   # Task 15
```

## Config Example (`~/.glue/config.yaml`)

```yaml
provider: anthropic
model: claude-sonnet-4-6

web:
  fetch:
    timeout_seconds: 30
    max_bytes: 5242880          # 5MB
    max_tokens: 50000
    allow_jina_fallback: true
    jina_api_key: "jina_..."   # optional

  search:
    provider: brave             # brave | tavily | firecrawl | auto
    max_results: 5
    timeout_seconds: 15
    brave_api_key: "BSA..."
    tavily_api_key: "tvly-..."
    firecrawl_api_key: "fc-..."
```

Environment variables (override config file):
- `BRAVE_API_KEY` / `TAVILY_API_KEY` / `FIRECRAWL_API_KEY`
- `JINA_API_KEY`
- `GLUE_SEARCH_PROVIDER` (override auto-detection)
