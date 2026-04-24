import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:glue/src/web/web_config.dart';
import 'package:glue/src/web/fetch/html_extractor.dart';
import 'package:glue/src/web/fetch/html_to_markdown.dart';
import 'package:glue/src/web/fetch/jina_reader_client.dart';
import 'package:glue/src/web/fetch/ocr_client.dart';
import 'package:glue/src/web/fetch/pdf_text_extractor.dart';
import 'package:glue/src/web/fetch/truncation.dart';
import 'package:glue/src/utils.dart';

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
  final PdfConfig pdfConfig;
  final http.Client _client;
  late final JinaReaderClient? _jinaClient;
  late final PdfTextExtractor _pdfExtractor;
  late final OcrClient? _ocrClient;

  WebFetchClient(
      {required this.config, PdfConfig? pdfConfig, http.Client? client})
      : pdfConfig = pdfConfig ?? const PdfConfig(),
        _client = client ?? http.Client() {
    _jinaClient = config.allowJinaFallback
        ? JinaReaderClient(
            baseUrl: config.jinaBaseUrl,
            apiKey: config.jinaApiKey,
            timeoutSeconds: config.timeoutSeconds,
            client: client,
          )
        : null;
    _pdfExtractor = PdfTextExtractor(
      timeoutSeconds: this.pdfConfig.timeoutSeconds,
    );
    _ocrClient =
        this.pdfConfig.enableOcrFallback && this.pdfConfig.hasOcrCredentials
            ? OcrClient.fromConfig(this.pdfConfig, client: client)
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

    // Single GET — route by content-type / magic bytes.
    try {
      final response = await _client.get(uri, headers: {
        'Accept': 'text/markdown, text/plain;q=0.9, '
            'text/html;q=0.8, application/pdf;q=0.7, */*;q=0.1',
        'User-Agent': 'Glue/0.1 (coding-agent)',
      }).timeout(config.timeoutSeconds.seconds);

      if (response.statusCode != 200) {
        // Fall through to Jina.
      } else {
        final contentType = response.headers['content-type'] ?? '';

        // Route 1: Markdown response.
        if (contentType.contains('text/markdown')) {
          if (response.bodyBytes.length > config.maxBytes) {
            return WebFetchResult.withError(
              url: url,
              error: 'Response too large: ${response.bodyBytes.length} bytes '
                  '(max ${config.maxBytes})',
            );
          }
          final truncated =
              TokenTruncation.truncate(response.body, maxTokens: budget);
          return WebFetchResult(
            url: url,
            markdown: truncated,
            estimatedTokens: TokenTruncation.estimateTokens(truncated),
          );
        }

        // Route 2: PDF (by content-type or magic bytes).
        if (PdfTextExtractor.isPdfContentType(contentType) ||
            PdfTextExtractor.isPdfContent(response.bodyBytes)) {
          final pdfResult = await _handlePdfResponse(uri, response, budget);
          if (pdfResult != null) return pdfResult;
        }

        // Route 3: HTML / text.
        if (contentType.contains('text/') || contentType.contains('html')) {
          final htmlResult = _convertHtmlResponse(uri, response, budget);
          if (htmlResult != null && htmlResult.isSuccess) return htmlResult;
        }
      }
    } catch (_) {}

    // Fallback: Jina Reader.
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

  WebFetchResult? _convertHtmlResponse(
    Uri uri,
    http.Response response,
    int maxTokens,
  ) {
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

  Future<WebFetchResult?> _handlePdfResponse(
    Uri uri,
    http.Response response,
    int maxTokens,
  ) async {
    if (response.bodyBytes.length > pdfConfig.maxBytes) {
      return WebFetchResult.withError(
        url: uri.toString(),
        error: 'PDF too large: ${response.bodyBytes.length} bytes '
            '(max ${pdfConfig.maxBytes})',
      );
    }

    // Try pdftotext CLI.
    final pdftotextAvailable = await PdfTextExtractor.checkPdftotextAvailable();
    if (pdftotextAvailable) {
      final result = await _pdfExtractor.extract(response.bodyBytes);
      if (result.isSuccess) {
        final truncated =
            TokenTruncation.truncate(result.text!, maxTokens: maxTokens);
        return WebFetchResult(
          url: uri.toString(),
          markdown: truncated,
          title: _extractPdfFilename(uri),
          estimatedTokens: TokenTruncation.estimateTokens(truncated),
        );
      }
    }

    // OCR fallback for scanned PDFs.
    if (_ocrClient != null) {
      final ocrText = await _ocrClient.extractText(response.bodyBytes);
      if (ocrText != null && ocrText.trim().isNotEmpty) {
        final truncated =
            TokenTruncation.truncate(ocrText, maxTokens: maxTokens);
        return WebFetchResult(
          url: uri.toString(),
          markdown: truncated,
          title: _extractPdfFilename(uri),
          estimatedTokens: TokenTruncation.estimateTokens(truncated),
        );
      }
    }

    if (!pdftotextAvailable) {
      return WebFetchResult.withError(
        url: uri.toString(),
        error: 'PDF detected but pdftotext is not installed. '
            'Install poppler-utils (apt install poppler-utils / '
            'brew install poppler) or configure OCR API keys.',
      );
    }

    return WebFetchResult.withError(
      url: uri.toString(),
      error: 'PDF text extraction returned empty content. '
          'This may be a scanned PDF — configure MISTRAL_API_KEY '
          'or OPENAI_API_KEY for OCR fallback.',
    );
  }

  String? _extractPdfFilename(Uri uri) {
    final path = uri.path;
    if (path.endsWith('.pdf')) {
      final segments = path.split('/');
      return segments.last.replaceAll('.pdf', '');
    }
    return null;
  }
}
