import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:glue/src/web/web_config.dart';
import 'package:glue/src/web/fetch/html_extractor.dart';
import 'package:glue/src/web/fetch/html_to_markdown.dart';
import 'package:glue/src/web/fetch/jina_reader_client.dart';
import 'package:glue/src/web/fetch/truncation.dart';

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
        final jinaResult = await _jinaClient.fetch(url);
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

    if (!contentType.contains('text/') && !contentType.contains('html')) {
      return null;
    }

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
