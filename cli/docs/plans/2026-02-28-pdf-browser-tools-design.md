# PDF Extraction & Web Browser Tools Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add PDF text extraction to the existing `web_fetch` pipeline and introduce a new `web_browser` tool backed by Chrome DevTools Protocol — pure Dart, configurable backends, session-scoped lifecycle.

**Architecture:** Two features: (1) PDF extraction integrates as a new stage in `WebFetchClient`, using `pdftotext` CLI for text extraction with OCR API fallback (Mistral OCR Small / OpenAI vision) for scanned documents; (2) Browser tool uses a 3-layer design — `BrowserEndpointProvider` for provisioning (local/Docker/cloud), `BrowserManager` for session-scoped CDP connection management, and `BrowserTool` as the thin `Tool` wrapper.

**Tech Stack:** Dart 3.4+, `package:puppeteer` (v3.20.0, CDP communication), `package:http` (already in deps), existing `Tool` base class, existing `GlueConfig`/`WebConfig` pattern, existing `DockerConfig`/`SessionState` pattern.

**Note on PDF extraction:** `syncfusion_flutter_pdf` was initially considered but requires the Flutter SDK (depends on `flutter`, `syncfusion_flutter_core`), which is incompatible with Glue's pure Dart CLI. Instead, we use `pdftotext` (from poppler-utils, universally available) via `Process.run` for reliable text extraction, with LLM-based OCR fallback for scanned PDFs. This is more robust for a CLI tool and adds zero dependencies.

---

## Phase 1: PDF Extraction

### Task 1: PDF config model + constants

**Files:**
- Modify: `cli/lib/src/config/constants.dart`
- Modify: `cli/lib/src/web/web_config.dart`
- Test: `cli/test/web/web_config_test.dart` (extend existing)

**Step 1: Add PDF constants to `AppConstants`**

Add to `cli/lib/src/config/constants.dart` inside the class body, after the web tool constants:

```dart
  // PDF extraction configuration
  static const int pdfMaxBytes = 20 * 1024 * 1024; // 20MB
  static const int pdfTimeoutSeconds = 60;
```

**Step 2: Add `PdfConfig` to `web_config.dart`**

Add the following enum and class to `cli/lib/src/web/web_config.dart`, before the `WebConfig` class:

```dart
/// Supported OCR providers for scanned PDF fallback.
enum OcrProviderType { mistral, openai }

/// Configuration for PDF text extraction.
class PdfConfig {
  final int maxBytes;
  final int timeoutSeconds;
  final bool enableOcrFallback;
  final OcrProviderType ocrProvider;
  final String? mistralApiKey;
  final String mistralModel;
  final String? openaiApiKey;
  final String openaiModel;

  const PdfConfig({
    this.maxBytes = AppConstants.pdfMaxBytes,
    this.timeoutSeconds = AppConstants.pdfTimeoutSeconds,
    this.enableOcrFallback = true,
    this.ocrProvider = OcrProviderType.mistral,
    this.mistralApiKey,
    this.mistralModel = 'mistral-ocr-small',
    this.openaiApiKey,
    this.openaiModel = 'gpt-4.1-mini',
  });

  /// Whether OCR is available (has at least one API key configured).
  bool get hasOcrCredentials {
    if (ocrProvider == OcrProviderType.mistral) {
      return mistralApiKey != null && mistralApiKey!.isNotEmpty;
    }
    return openaiApiKey != null && openaiApiKey!.isNotEmpty;
  }
}
```

**Step 3: Add `pdf` field to `WebConfig`**

Modify the `WebConfig` class in `cli/lib/src/web/web_config.dart`:

```dart
class WebConfig {
  final WebFetchConfig fetch;
  final WebSearchConfig search;
  final PdfConfig pdf;

  const WebConfig({
    this.fetch = const WebFetchConfig(),
    this.search = const WebSearchConfig(),
    this.pdf = const PdfConfig(),
  });
}
```

**Step 4: Extend tests**

Add to `cli/test/web/web_config_test.dart`:

```dart
  group('PdfConfig', () {
    test('defaults are sensible', () {
      const config = PdfConfig();
      expect(config.maxBytes, 20 * 1024 * 1024);
      expect(config.timeoutSeconds, 60);
      expect(config.enableOcrFallback, isTrue);
      expect(config.ocrProvider, OcrProviderType.mistral);
    });

    test('hasOcrCredentials returns false when no keys set', () {
      const config = PdfConfig();
      expect(config.hasOcrCredentials, isFalse);
    });

    test('hasOcrCredentials returns true with mistral key', () {
      const config = PdfConfig(mistralApiKey: 'key');
      expect(config.hasOcrCredentials, isTrue);
    });

    test('hasOcrCredentials checks openai key when provider is openai', () {
      const config = PdfConfig(
        ocrProvider: OcrProviderType.openai,
        openaiApiKey: 'key',
      );
      expect(config.hasOcrCredentials, isTrue);
    });

    test('hasOcrCredentials false for empty string key', () {
      const config = PdfConfig(mistralApiKey: '');
      expect(config.hasOcrCredentials, isFalse);
    });
  });
```

**Step 5: Run tests**

Run: `cd cli && dart test test/web/web_config_test.dart`
Expected: all pass

**Step 6: Commit**

```bash
git add cli/lib/src/config/constants.dart cli/lib/src/web/web_config.dart cli/test/web/web_config_test.dart
git commit -m "feat(pdf): add PdfConfig model with OCR provider settings"
```

---

### Task 2: Wire PDF config into `GlueConfig`

**Files:**
- Modify: `cli/lib/src/config/glue_config.dart`

**Step 1: Add PDF config resolution to `GlueConfig.load()`**

In `cli/lib/src/config/glue_config.dart`, inside the `GlueConfig.load()` factory, add PDF resolution after the web search config block (before `final webConfig = WebConfig(...)`):

```dart
    // 2e. Resolve PDF configuration.
    final pdfSection = webSection?['pdf'] as Map?;
    final mistralApiKey = Platform.environment['MISTRAL_API_KEY'] ??
        pdfSection?['mistral_api_key'] as String?;
    final pdfOpenaiApiKey = Platform.environment['OPENAI_API_KEY'] ??
        pdfSection?['openai_api_key'] as String?;
    final ocrProviderStr = Platform.environment['GLUE_OCR_PROVIDER'] ??
        pdfSection?['ocr_provider'] as String?;
    final ocrProvider = ocrProviderStr != null
        ? OcrProviderType.values.firstWhere(
            (p) => p.name == ocrProviderStr,
            orElse: () => OcrProviderType.mistral,
          )
        : OcrProviderType.mistral;

    final pdfConfig = PdfConfig(
      maxBytes:
          pdfSection?['max_bytes'] as int? ?? AppConstants.pdfMaxBytes,
      timeoutSeconds: pdfSection?['timeout_seconds'] as int? ??
          AppConstants.pdfTimeoutSeconds,
      enableOcrFallback:
          pdfSection?['enable_ocr_fallback'] as bool? ?? true,
      ocrProvider: ocrProvider,
      mistralApiKey: mistralApiKey,
      openaiApiKey: pdfOpenaiApiKey,
    );
```

**Step 2: Add `pdf` to `WebConfig` constructor call**

Update the `final webConfig = WebConfig(...)` call to include `pdf`:

```dart
    final webConfig = WebConfig(
      fetch: webFetchConfig,
      search: webSearchConfig,
      pdf: pdfConfig,
    );
```

**Step 3: Add import for `OcrProviderType`**

The `OcrProviderType` enum is already in `web_config.dart` which is already imported.

**Step 4: Verify**

Run: `cd cli && dart analyze`
Expected: no warnings

**Step 5: Commit**

```bash
git add cli/lib/src/config/glue_config.dart
git commit -m "feat(pdf): wire PdfConfig into GlueConfig.load()"
```

---

### Task 3: `PdfTextExtractor` (pdftotext wrapper)

**Files:**
- Create: `cli/lib/src/web/fetch/pdf_text_extractor.dart`
- Test: `cli/test/web/fetch/pdf_text_extractor_test.dart`

**Step 1: Write tests**

Create `cli/test/web/fetch/pdf_text_extractor_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:glue/src/web/fetch/pdf_text_extractor.dart';

void main() {
  group('PdfTextExtractor', () {
    test('isPdfContent detects PDF magic bytes', () {
      final pdfBytes = Uint8List.fromList(
        '%PDF-1.4 fake content'.codeUnits,
      );
      expect(PdfTextExtractor.isPdfContent(pdfBytes), isTrue);
    });

    test('isPdfContent rejects non-PDF bytes', () {
      final htmlBytes = Uint8List.fromList(
        '<html>not a pdf</html>'.codeUnits,
      );
      expect(PdfTextExtractor.isPdfContent(htmlBytes), isFalse);
    });

    test('isPdfContent rejects empty bytes', () {
      expect(PdfTextExtractor.isPdfContent(Uint8List(0)), isFalse);
    });

    test('isPdfContentType detects application/pdf', () {
      expect(PdfTextExtractor.isPdfContentType('application/pdf'), isTrue);
    });

    test('isPdfContentType detects with charset', () {
      expect(
        PdfTextExtractor.isPdfContentType(
          'application/pdf; charset=utf-8',
        ),
        isTrue,
      );
    });

    test('isPdfContentType rejects text/html', () {
      expect(PdfTextExtractor.isPdfContentType('text/html'), isFalse);
    });

    test('checkPdftotextAvailable returns bool', () async {
      final available = await PdfTextExtractor.checkPdftotextAvailable();
      expect(available, isA<bool>());
    });
  });
}
```

**Step 2: Implement**

Create `cli/lib/src/web/fetch/pdf_text_extractor.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Result of PDF text extraction.
class PdfExtractionResult {
  final String? text;
  final String? error;
  final int pageCount;

  PdfExtractionResult({this.text, this.error, this.pageCount = 0});

  bool get isSuccess => text != null && text!.trim().isNotEmpty && error == null;

  factory PdfExtractionResult.withError(String error) =>
      PdfExtractionResult(error: error);
}

/// Extracts text from PDF bytes using the `pdftotext` CLI tool.
///
/// pdftotext is part of poppler-utils, available on macOS (brew install
/// poppler), Linux (apt install poppler-utils), and Windows (scoop/choco).
class PdfTextExtractor {
  final int timeoutSeconds;

  PdfTextExtractor({this.timeoutSeconds = 60});

  /// Check if the PDF magic bytes are present.
  static bool isPdfContent(Uint8List bytes) {
    if (bytes.length < 5) return false;
    // %PDF-
    return bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46 &&
        bytes[4] == 0x2D;
  }

  /// Check if a content-type header indicates PDF.
  static bool isPdfContentType(String contentType) =>
      contentType.toLowerCase().contains('application/pdf');

  /// Check whether `pdftotext` is available on this system.
  static Future<bool> checkPdftotextAvailable() async {
    try {
      final result = await Process.run('pdftotext', ['-v']);
      // pdftotext -v writes version to stderr and exits 0 or 99
      return result.exitCode == 0 || result.exitCode == 99;
    } catch (_) {
      return false;
    }
  }

  /// Extract text from PDF [bytes] using pdftotext.
  ///
  /// Writes bytes to a temp file, runs pdftotext, reads output, cleans up.
  /// Returns null if pdftotext is not available or extraction fails.
  Future<PdfExtractionResult> extract(Uint8List bytes) async {
    final tempDir = await Directory.systemTemp.createTemp('glue-pdf-');
    final inputFile = File(p.join(tempDir.path, 'input.pdf'));
    final outputFile = File(p.join(tempDir.path, 'output.txt'));

    try {
      await inputFile.writeAsBytes(bytes);

      final result = await Process.run(
        'pdftotext',
        ['-layout', inputFile.path, outputFile.path],
      ).timeout(Duration(seconds: timeoutSeconds));

      if (result.exitCode != 0) {
        final stderr = (result.stderr as String).trim();
        return PdfExtractionResult.withError(
          'pdftotext failed (exit ${result.exitCode}): $stderr',
        );
      }

      if (!await outputFile.exists()) {
        return PdfExtractionResult.withError(
          'pdftotext produced no output file',
        );
      }

      final text = await outputFile.readAsString();
      return PdfExtractionResult(text: text);
    } on TimeoutException {
      return PdfExtractionResult.withError(
        'pdftotext timed out after $timeoutSeconds seconds',
      );
    } catch (e) {
      return PdfExtractionResult.withError('PDF extraction failed: $e');
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }
}
```

**Step 3: Run tests**

Run: `cd cli && dart test test/web/fetch/pdf_text_extractor_test.dart`
Expected: all pass

**Step 4: Commit**

```bash
git add cli/lib/src/web/fetch/pdf_text_extractor.dart cli/test/web/fetch/pdf_text_extractor_test.dart
git commit -m "feat(pdf): add PdfTextExtractor using pdftotext CLI"
```

---

### Task 4: OCR fallback client

**Files:**
- Create: `cli/lib/src/web/fetch/ocr_client.dart`
- Test: `cli/test/web/fetch/ocr_client_test.dart`

**Step 1: Write tests**

Create `cli/test/web/fetch/ocr_client_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:glue/src/web/fetch/ocr_client.dart';
import 'package:glue/src/web/web_config.dart';

void main() {
  group('OcrClient', () {
    test('creates Mistral request body correctly', () {
      final client = OcrClient(
        provider: OcrProviderType.mistral,
        apiKey: 'test-key',
        model: 'mistral-ocr-small',
      );
      final body = client.buildMistralRequestBody(
        Uint8List.fromList([1, 2, 3]),
      );
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['model'], 'mistral-ocr-small');
      expect(json['document'], isNotNull);
    });

    test('creates OpenAI request body correctly', () {
      final client = OcrClient(
        provider: OcrProviderType.openai,
        apiKey: 'test-key',
        model: 'gpt-4.1-mini',
      );
      final body = client.buildOpenAIRequestBody(
        Uint8List.fromList([1, 2, 3]),
      );
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['model'], 'gpt-4.1-mini');
      expect(json['messages'], isNotEmpty);
    });

    test('headers include authorization', () {
      final client = OcrClient(
        provider: OcrProviderType.mistral,
        apiKey: 'test-key',
        model: 'mistral-ocr-small',
      );
      expect(client.headers['Authorization'], 'Bearer test-key');
    });
  });
}
```

**Step 2: Implement**

Create `cli/lib/src/web/fetch/ocr_client.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:glue/src/web/web_config.dart';

/// Client for OCR-based PDF text extraction using LLM vision APIs.
///
/// Supports Mistral OCR Small (pixtral-based) and OpenAI vision models.
/// Used as a fallback when pdftotext returns empty text (scanned PDFs).
class OcrClient {
  final OcrProviderType provider;
  final String apiKey;
  final String model;
  final int timeoutSeconds;

  OcrClient({
    required this.provider,
    required this.apiKey,
    required this.model,
    this.timeoutSeconds = 120,
  });

  factory OcrClient.fromConfig(PdfConfig config) => OcrClient(
        provider: config.ocrProvider,
        apiKey: config.ocrProvider == OcrProviderType.mistral
            ? config.mistralApiKey ?? ''
            : config.openaiApiKey ?? '',
        model: config.ocrProvider == OcrProviderType.mistral
            ? config.mistralModel
            : config.openaiModel,
      );

  Map<String, String> get headers => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      };

  /// Extract text from PDF bytes via OCR API.
  /// Returns extracted text or null on failure.
  Future<String?> extractText(Uint8List pdfBytes) async {
    try {
      return switch (provider) {
        OcrProviderType.mistral => await _extractViaMistral(pdfBytes),
        OcrProviderType.openai => await _extractViaOpenAI(pdfBytes),
      };
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _extractViaMistral(Uint8List pdfBytes) async {
    final uri = Uri.parse('https://api.mistral.ai/v1/ocr');
    final body = buildMistralRequestBody(pdfBytes);

    final response = await http
        .post(uri, headers: headers, body: body)
        .timeout(Duration(seconds: timeoutSeconds));

    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final pages = json['pages'] as List<dynamic>?;
    if (pages == null || pages.isEmpty) return null;

    final buf = StringBuffer();
    for (final page in pages) {
      final pageMap = page as Map<String, dynamic>;
      final markdown = pageMap['markdown'] as String? ?? '';
      if (markdown.isNotEmpty) {
        buf.writeln(markdown);
        buf.writeln();
      }
    }
    return buf.toString().trim().isEmpty ? null : buf.toString();
  }

  Future<String?> _extractViaOpenAI(Uint8List pdfBytes) async {
    // OpenAI vision doesn't natively support PDF — convert first page
    // to a data URL. For multi-page PDFs, this is a best-effort approach.
    final uri = Uri.parse('https://api.openai.com/v1/chat/completions');
    final body = buildOpenAIRequestBody(pdfBytes);

    final response = await http
        .post(uri, headers: headers, body: body)
        .timeout(Duration(seconds: timeoutSeconds));

    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return null;

    final message =
        (choices[0] as Map<String, dynamic>)['message'] as Map<String, dynamic>;
    return message['content'] as String?;
  }

  String buildMistralRequestBody(Uint8List pdfBytes) {
    final base64Pdf = base64Encode(pdfBytes);
    return jsonEncode({
      'model': model,
      'document': {
        'type': 'document_url',
        'document_url': 'data:application/pdf;base64,$base64Pdf',
      },
    });
  }

  String buildOpenAIRequestBody(Uint8List pdfBytes) {
    final base64Pdf = base64Encode(pdfBytes);
    return jsonEncode({
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': 'Extract all text from this PDF document. '
                  'Return the text content as clean markdown, '
                  'preserving headings, lists, and structure.',
            },
            {
              'type': 'file',
              'file': {
                'filename': 'document.pdf',
                'file_data': 'data:application/pdf;base64,$base64Pdf',
              },
            },
          ],
        },
      ],
    });
  }
}
```

**Step 3: Run tests**

Run: `cd cli && dart test test/web/fetch/ocr_client_test.dart`
Expected: all pass

**Step 4: Commit**

```bash
git add cli/lib/src/web/fetch/ocr_client.dart cli/test/web/fetch/ocr_client_test.dart
git commit -m "feat(pdf): add OcrClient for Mistral/OpenAI scanned PDF fallback"
```

---

### Task 5: Integrate PDF extraction into `WebFetchClient`

**Files:**
- Modify: `cli/lib/src/web/fetch/web_fetch_client.dart`
- Test: `cli/test/web/fetch/web_fetch_client_test.dart` (extend existing)

**Step 1: Add PDF imports and config**

Add imports at the top of `cli/lib/src/web/fetch/web_fetch_client.dart`:

```dart
import 'package:glue/src/web/fetch/pdf_text_extractor.dart';
import 'package:glue/src/web/fetch/ocr_client.dart';
```

**Step 2: Add `PdfConfig` parameter to `WebFetchClient`**

Modify the `WebFetchClient` class to accept and store a `PdfConfig`:

```dart
class WebFetchClient {
  final WebFetchConfig config;
  final PdfConfig pdfConfig;
  late final JinaReaderClient? _jinaClient;
  late final PdfTextExtractor _pdfExtractor;
  late final OcrClient? _ocrClient;

  WebFetchClient({required this.config, PdfConfig? pdfConfig})
      : pdfConfig = pdfConfig ?? const PdfConfig() {
    _jinaClient = config.allowJinaFallback
        ? JinaReaderClient(
            baseUrl: config.jinaBaseUrl,
            apiKey: config.jinaApiKey,
            timeoutSeconds: config.timeoutSeconds,
          )
        : null;
    _pdfExtractor = PdfTextExtractor(
      timeoutSeconds: this.pdfConfig.timeoutSeconds,
    );
    _ocrClient = this.pdfConfig.enableOcrFallback &&
            this.pdfConfig.hasOcrCredentials
        ? OcrClient.fromConfig(this.pdfConfig)
        : null;
  }
```

**Step 3: Add PDF stage to `_htmlFetchAndConvert`**

In the `_htmlFetchAndConvert` method, after checking the content type, add PDF detection. Alternatively, add a new `_tryPdfExtraction` method and call it from `fetch()` between stage 1 and stage 2.

Add the following method to `WebFetchClient`:

```dart
  Future<WebFetchResult?> _tryPdfExtraction(
    Uri uri,
    int maxTokens,
  ) async {
    final response = await http
        .get(uri, headers: {
          'Accept': '*/*',
          'User-Agent': 'Glue/0.1 (coding-agent)',
        })
        .timeout(Duration(seconds: config.timeoutSeconds));

    if (response.statusCode != 200) return null;

    final contentType = response.headers['content-type'] ?? '';
    if (!PdfTextExtractor.isPdfContentType(contentType) &&
        !PdfTextExtractor.isPdfContent(response.bodyBytes)) {
      return null;
    }

    if (response.bodyBytes.length > pdfConfig.maxBytes) {
      return WebFetchResult.withError(
        url: uri.toString(),
        error: 'PDF too large: ${response.bodyBytes.length} bytes '
            '(max ${pdfConfig.maxBytes})',
      );
    }

    // Stage A: Try pdftotext CLI.
    final pdftotextAvailable =
        await PdfTextExtractor.checkPdftotextAvailable();
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

    // Stage B: OCR fallback for scanned PDFs.
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

    // pdftotext not available and no OCR — return error with guidance.
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
```

**Step 4: Insert PDF stage into `fetch()` pipeline**

In the `fetch()` method, add the PDF stage between the markdown fetch stage and the HTML stage. After `// Stage 1: Try Accept: text/markdown.` block and before `// Stage 2: HTML fetch → extract → convert.`:

```dart
    // Stage 1.5: Try PDF extraction.
    try {
      final pdfResult = await _tryPdfExtraction(uri, budget);
      if (pdfResult != null) return pdfResult;
    } catch (_) {}
```

**Step 5: Extend tests**

Add to `cli/test/web/fetch/web_fetch_client_test.dart`:

```dart
    test('detects PDF content type in URL', () {
      // Just test the helper
      expect(PdfTextExtractor.isPdfContentType('application/pdf'), isTrue);
      expect(
        PdfTextExtractor.isPdfContentType('application/pdf; charset=binary'),
        isTrue,
      );
      expect(PdfTextExtractor.isPdfContentType('text/html'), isFalse);
    });

    test('constructs with PdfConfig', () {
      final client = WebFetchClient(
        config: const WebFetchConfig(allowJinaFallback: false),
        pdfConfig: const PdfConfig(enableOcrFallback: false),
      );
      expect(client, isNotNull);
    });
```

**Step 6: Run tests**

Run: `cd cli && dart test test/web/fetch/`
Expected: all pass

**Step 7: Commit**

```bash
git add cli/lib/src/web/fetch/web_fetch_client.dart cli/test/web/fetch/web_fetch_client_test.dart
git commit -m "feat(pdf): integrate PDF extraction into WebFetchClient pipeline"
```

---

### Task 6: Update `WebFetchTool` and `App` wiring

**Files:**
- Modify: `cli/lib/src/tools/web_fetch_tool.dart`
- Modify: `cli/lib/src/app.dart`

**Step 1: Update `WebFetchTool` to pass `PdfConfig`**

Modify `cli/lib/src/tools/web_fetch_tool.dart`:

```dart
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/web/web_config.dart';
import 'package:glue/src/web/fetch/web_fetch_client.dart';

class WebFetchTool extends Tool {
  final WebFetchClient _client;

  WebFetchTool(WebFetchConfig config, {PdfConfig? pdfConfig})
      : _client = WebFetchClient(config: config, pdfConfig: pdfConfig);
```

**Step 2: Update tool registration in `App.create()`**

In `cli/lib/src/app.dart`, update the `web_fetch` tool registration:

```dart
      'web_fetch': WebFetchTool(config.webConfig.fetch,
          pdfConfig: config.webConfig.pdf),
```

**Step 3: Update `web_fetch` tool description**

In `WebFetchTool`, update the description to mention PDF support:

```dart
  @override
  String get description =>
      'Fetch the content of a web page or PDF at the given URL and return it '
      'as clean markdown. Handles static HTML pages and PDF documents. '
      'Does not execute JavaScript — use web_browser for dynamic pages.';
```

**Step 4: Verify**

Run: `cd cli && dart analyze`
Expected: no warnings

Run: `cd cli && dart test`
Expected: all pass

**Step 5: Commit**

```bash
git add cli/lib/src/tools/web_fetch_tool.dart cli/lib/src/app.dart
git commit -m "feat(pdf): wire PdfConfig into WebFetchTool and App"
```

---

## Phase 2: Web Browser Tool

### Task 7: Add `package:puppeteer` dependency

**Files:**
- Modify: `cli/pubspec.yaml`

**Step 1: Add the dependency**

Add `puppeteer: ^3.20.0` to pubspec.yaml dependencies:

```yaml
dependencies:
  args: ^2.7.0
  html: ^0.15.5
  http: ^1.6.0
  path: ^1.9.1
  puppeteer: ^3.20.0
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
git commit -m "deps: add package:puppeteer for web_browser CDP communication"
```

---

### Task 8: Browser config model + constants

**Files:**
- Modify: `cli/lib/src/config/constants.dart`
- Create: `cli/lib/src/web/browser/browser_config.dart`
- Test: `cli/test/web/browser/browser_config_test.dart`

**Step 1: Add browser constants to `AppConstants`**

Add to `cli/lib/src/config/constants.dart`:

```dart
  // Browser tool configuration
  static const int browserNavigationTimeoutSeconds = 30;
  static const int browserActionTimeoutSeconds = 10;
  static const int browserDockerPort = 3000;
  static const String browserDockerImage = 'browserless/chrome:latest';
```

**Step 2: Create `BrowserConfig` model**

Create `cli/lib/src/web/browser/browser_config.dart`:

```dart
import 'package:glue/src/config/constants.dart';

/// Supported browser backend types.
enum BrowserBackend { local, docker, steel, browserbase, browserless }

/// Configuration for the web_browser tool.
class BrowserConfig {
  final BrowserBackend backend;
  final bool headed;
  final int navigationTimeoutSeconds;
  final int actionTimeoutSeconds;

  // Docker-specific settings.
  final String dockerImage;
  final int dockerPort;

  // Cloud provider credentials.
  final String? steelApiKey;
  final String? browserbaseApiKey;
  final String? browserbaseProjectId;
  final String? browserlessBaseUrl;
  final String? browserlessApiKey;

  const BrowserConfig({
    this.backend = BrowserBackend.local,
    this.headed = false,
    this.navigationTimeoutSeconds =
        AppConstants.browserNavigationTimeoutSeconds,
    this.actionTimeoutSeconds = AppConstants.browserActionTimeoutSeconds,
    this.dockerImage = AppConstants.browserDockerImage,
    this.dockerPort = AppConstants.browserDockerPort,
    this.steelApiKey,
    this.browserbaseApiKey,
    this.browserbaseProjectId,
    this.browserlessBaseUrl,
    this.browserlessApiKey,
  });

  /// Whether the selected backend has valid credentials.
  bool get isConfigured => switch (backend) {
        BrowserBackend.local => true,
        BrowserBackend.docker => true,
        BrowserBackend.steel =>
          steelApiKey != null && steelApiKey!.isNotEmpty,
        BrowserBackend.browserbase =>
          browserbaseApiKey != null &&
              browserbaseApiKey!.isNotEmpty &&
              browserbaseProjectId != null &&
              browserbaseProjectId!.isNotEmpty,
        BrowserBackend.browserless =>
          browserlessApiKey != null && browserlessApiKey!.isNotEmpty,
      };
}
```

**Step 3: Write tests**

Create `cli/test/web/browser/browser_config_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:glue/src/web/browser/browser_config.dart';

void main() {
  group('BrowserConfig', () {
    test('defaults to local backend', () {
      const config = BrowserConfig();
      expect(config.backend, BrowserBackend.local);
      expect(config.headed, isFalse);
    });

    test('local is always configured', () {
      const config = BrowserConfig(backend: BrowserBackend.local);
      expect(config.isConfigured, isTrue);
    });

    test('docker is always configured', () {
      const config = BrowserConfig(backend: BrowserBackend.docker);
      expect(config.isConfigured, isTrue);
    });

    test('steel requires API key', () {
      const config = BrowserConfig(backend: BrowserBackend.steel);
      expect(config.isConfigured, isFalse);

      const configured = BrowserConfig(
        backend: BrowserBackend.steel,
        steelApiKey: 'key',
      );
      expect(configured.isConfigured, isTrue);
    });

    test('browserbase requires API key and project ID', () {
      const noKey = BrowserConfig(backend: BrowserBackend.browserbase);
      expect(noKey.isConfigured, isFalse);

      const onlyKey = BrowserConfig(
        backend: BrowserBackend.browserbase,
        browserbaseApiKey: 'key',
      );
      expect(onlyKey.isConfigured, isFalse);

      const both = BrowserConfig(
        backend: BrowserBackend.browserbase,
        browserbaseApiKey: 'key',
        browserbaseProjectId: 'proj',
      );
      expect(both.isConfigured, isTrue);
    });

    test('browserless requires API key', () {
      const config = BrowserConfig(backend: BrowserBackend.browserless);
      expect(config.isConfigured, isFalse);

      const configured = BrowserConfig(
        backend: BrowserBackend.browserless,
        browserlessApiKey: 'key',
      );
      expect(configured.isConfigured, isTrue);
    });

    test('empty string key is treated as not configured', () {
      const config = BrowserConfig(
        backend: BrowserBackend.steel,
        steelApiKey: '',
      );
      expect(config.isConfigured, isFalse);
    });
  });
}
```

**Step 4: Run tests**

Run: `cd cli && dart test test/web/browser/browser_config_test.dart`
Expected: all pass

**Step 5: Commit**

```bash
git add cli/lib/src/config/constants.dart cli/lib/src/web/browser/browser_config.dart cli/test/web/browser/browser_config_test.dart
git commit -m "feat(browser): add BrowserConfig model with backend validation"
```

---

### Task 9: Wire `BrowserConfig` into `WebConfig` and `GlueConfig`

**Files:**
- Modify: `cli/lib/src/web/web_config.dart`
- Modify: `cli/lib/src/config/glue_config.dart`

**Step 1: Add `BrowserConfig` to `WebConfig`**

Add import at top of `cli/lib/src/web/web_config.dart`:

```dart
import 'package:glue/src/web/browser/browser_config.dart';
```

Modify `WebConfig`:

```dart
class WebConfig {
  final WebFetchConfig fetch;
  final WebSearchConfig search;
  final PdfConfig pdf;
  final BrowserConfig browser;

  const WebConfig({
    this.fetch = const WebFetchConfig(),
    this.search = const WebSearchConfig(),
    this.pdf = const PdfConfig(),
    this.browser = const BrowserConfig(),
  });
}
```

**Step 2: Add browser config resolution to `GlueConfig.load()`**

In `cli/lib/src/config/glue_config.dart`, add import:

```dart
import '../web/browser/browser_config.dart';
```

Add browser resolution block after the PDF config block (before `final webConfig = WebConfig(...)`):

```dart
    // 2f. Resolve browser configuration.
    final browserSection = webSection?['browser'] as Map?;
    final dockerBrowserSection = browserSection?['docker'] as Map?;
    final steelSection = browserSection?['steel'] as Map?;
    final browserbaseSection = browserSection?['browserbase'] as Map?;
    final browserlessSection = browserSection?['browserless'] as Map?;

    final browserBackendStr = Platform.environment['GLUE_BROWSER_BACKEND'] ??
        browserSection?['backend'] as String?;
    final browserBackend = browserBackendStr != null
        ? BrowserBackend.values.firstWhere(
            (b) => b.name == browserBackendStr,
            orElse: () => BrowserBackend.local,
          )
        : BrowserBackend.local;

    final browserConfig = BrowserConfig(
      backend: browserBackend,
      headed: browserSection?['headed'] as bool? ?? false,
      dockerImage: dockerBrowserSection?['image'] as String? ??
          AppConstants.browserDockerImage,
      dockerPort: dockerBrowserSection?['port'] as int? ??
          AppConstants.browserDockerPort,
      steelApiKey: Platform.environment['STEEL_API_KEY'] ??
          steelSection?['api_key'] as String?,
      browserbaseApiKey: Platform.environment['BROWSERBASE_API_KEY'] ??
          browserbaseSection?['api_key'] as String?,
      browserbaseProjectId: Platform.environment['BROWSERBASE_PROJECT_ID'] ??
          browserbaseSection?['project_id'] as String?,
      browserlessBaseUrl:
          browserlessSection?['base_url'] as String?,
      browserlessApiKey: Platform.environment['BROWSERLESS_API_KEY'] ??
          browserlessSection?['api_key'] as String?,
    );
```

**Step 3: Add `browser` to `WebConfig` constructor call**

Update the `final webConfig = WebConfig(...)` call:

```dart
    final webConfig = WebConfig(
      fetch: webFetchConfig,
      search: webSearchConfig,
      pdf: pdfConfig,
      browser: browserConfig,
    );
```

**Step 4: Verify**

Run: `cd cli && dart analyze`
Expected: no warnings

**Step 5: Commit**

```bash
git add cli/lib/src/web/web_config.dart cli/lib/src/config/glue_config.dart
git commit -m "feat(browser): wire BrowserConfig into WebConfig and GlueConfig"
```

---

### Task 10: `BrowserEndpoint` + `BrowserEndpointProvider` interface

**Files:**
- Create: `cli/lib/src/web/browser/browser_endpoint.dart`
- Test: `cli/test/web/browser/browser_endpoint_test.dart`

**Step 1: Write tests**

Create `cli/test/web/browser/browser_endpoint_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:glue/src/web/browser/browser_endpoint.dart';

void main() {
  group('BrowserEndpoint', () {
    test('holds CDP WebSocket URL', () {
      final endpoint = BrowserEndpoint(
        cdpWsUrl: 'ws://localhost:9222/devtools/browser/abc',
        backendName: 'local',
      );
      expect(endpoint.cdpWsUrl, 'ws://localhost:9222/devtools/browser/abc');
      expect(endpoint.backendName, 'local');
      expect(endpoint.viewUrl, isNull);
    });

    test('holds debug info for cloud providers', () {
      final endpoint = BrowserEndpoint(
        cdpWsUrl: 'wss://cloud.example.com/ws',
        backendName: 'steel',
        viewUrl: 'https://app.steel.dev/sessions/123',
        headed: false,
      );
      expect(endpoint.viewUrl, isNotNull);
    });

    test('debugFooter formats correctly', () {
      final endpoint = BrowserEndpoint(
        cdpWsUrl: 'ws://localhost:9222/devtools/browser/abc',
        backendName: 'local',
        headed: true,
      );
      final footer = endpoint.debugFooter;
      expect(footer, contains('local'));
      expect(footer, contains('headed'));
    });

    test('debugFooter includes view URL when present', () {
      final endpoint = BrowserEndpoint(
        cdpWsUrl: 'wss://cloud.example.com/ws',
        backendName: 'steel',
        viewUrl: 'https://app.steel.dev/sessions/123',
      );
      final footer = endpoint.debugFooter;
      expect(footer, contains('https://app.steel.dev/sessions/123'));
    });
  });
}
```

**Step 2: Implement**

Create `cli/lib/src/web/browser/browser_endpoint.dart`:

```dart
/// A provisioned browser endpoint with CDP WebSocket URL.
class BrowserEndpoint {
  final String cdpWsUrl;
  final String backendName;
  final bool headed;
  final String? viewUrl;
  final Future<void> Function()? _onClose;

  BrowserEndpoint({
    required this.cdpWsUrl,
    required this.backendName,
    this.headed = false,
    this.viewUrl,
    Future<void> Function()? onClose,
  }) : _onClose = onClose;

  /// Release the browser endpoint (stop container, close session, etc.).
  Future<void> close() async {
    if (_onClose != null) await _onClose();
  }

  /// Debug footer for tool results.
  String get debugFooter {
    final parts = <String>['---', 'Backend: $backendName'];
    if (headed) parts.add('Mode: headed');
    if (viewUrl != null) parts.add('View session: $viewUrl');
    return parts.join('\n');
  }
}

/// Interface for provisioning browser endpoints.
///
/// Implementations handle the specifics of launching or connecting
/// to a browser instance (local Chrome, Docker container, cloud API).
abstract class BrowserEndpointProvider {
  /// Human-readable name for logging and debug output.
  String get name;

  /// Whether this provider can be used (credentials available, etc.).
  bool get isAvailable;

  /// Provision a new browser endpoint.
  /// Caller must call [BrowserEndpoint.close] when done.
  Future<BrowserEndpoint> provision();
}
```

**Step 3: Run tests**

Run: `cd cli && dart test test/web/browser/browser_endpoint_test.dart`
Expected: all pass

**Step 4: Commit**

```bash
git add cli/lib/src/web/browser/browser_endpoint.dart cli/test/web/browser/browser_endpoint_test.dart
git commit -m "feat(browser): add BrowserEndpoint and BrowserEndpointProvider interface"
```

---

### Task 11: `LocalProvider` implementation

**Files:**
- Create: `cli/lib/src/web/browser/providers/local_provider.dart`
- Test: `cli/test/web/browser/providers/local_provider_test.dart`

**Step 1: Write tests**

Create `cli/test/web/browser/providers/local_provider_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:glue/src/web/browser/providers/local_provider.dart';
import 'package:glue/src/web/browser/browser_config.dart';

void main() {
  group('LocalProvider', () {
    test('has correct name', () {
      final provider = LocalProvider(const BrowserConfig());
      expect(provider.name, 'local');
    });

    test('is always available', () {
      final provider = LocalProvider(const BrowserConfig());
      expect(provider.isAvailable, isTrue);
    });

    test('respects headed config', () {
      final provider = LocalProvider(
        const BrowserConfig(headed: true),
      );
      expect(provider.headed, isTrue);
    });
  });
}
```

**Step 2: Implement**

Create `cli/lib/src/web/browser/providers/local_provider.dart`:

```dart
import 'package:puppeteer/puppeteer.dart' as pptr;

import 'package:glue/src/web/browser/browser_endpoint.dart';
import 'package:glue/src/web/browser/browser_config.dart';

/// Launches a local Chrome/Chromium instance via puppeteer.
///
/// Uses puppeteer's built-in Chrome download and management.
/// Supports headed mode for debugging.
class LocalProvider implements BrowserEndpointProvider {
  final BrowserConfig config;

  LocalProvider(this.config);

  bool get headed => config.headed;

  @override
  String get name => 'local';

  @override
  bool get isAvailable => true;

  @override
  Future<BrowserEndpoint> provision() async {
    final browser = await pptr.puppeteer.launch(
      headless: !config.headed,
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
      ],
    );

    return BrowserEndpoint(
      cdpWsUrl: browser.wsEndpoint,
      backendName: name,
      headed: config.headed,
      onClose: () async {
        await browser.close();
      },
    );
  }
}
```

**Step 3: Run tests**

Run: `cd cli && dart test test/web/browser/providers/local_provider_test.dart`
Expected: all pass (unit tests don't launch Chrome)

**Step 4: Commit**

```bash
git add cli/lib/src/web/browser/providers/local_provider.dart cli/test/web/browser/providers/local_provider_test.dart
git commit -m "feat(browser): add LocalProvider for local Chrome via puppeteer"
```

---

### Task 12: Cloud provider implementations

**Files:**
- Create: `cli/lib/src/web/browser/providers/steel_provider.dart`
- Create: `cli/lib/src/web/browser/providers/browserbase_provider.dart`
- Create: `cli/lib/src/web/browser/providers/browserless_provider.dart`
- Test: `cli/test/web/browser/providers/cloud_providers_test.dart`

**Step 1: Write tests**

Create `cli/test/web/browser/providers/cloud_providers_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:glue/src/web/browser/browser_config.dart';
import 'package:glue/src/web/browser/providers/steel_provider.dart';
import 'package:glue/src/web/browser/providers/browserbase_provider.dart';
import 'package:glue/src/web/browser/providers/browserless_provider.dart';

void main() {
  group('SteelProvider', () {
    test('has correct name', () {
      final provider = SteelProvider(apiKey: 'test-key');
      expect(provider.name, 'steel');
    });

    test('is available when API key is set', () {
      final provider = SteelProvider(apiKey: 'test-key');
      expect(provider.isAvailable, isTrue);
    });

    test('is not available without API key', () {
      final provider = SteelProvider(apiKey: null);
      expect(provider.isAvailable, isFalse);
    });
  });

  group('BrowserbaseProvider', () {
    test('has correct name', () {
      final provider = BrowserbaseProvider(
        apiKey: 'key',
        projectId: 'proj',
      );
      expect(provider.name, 'browserbase');
    });

    test('requires both API key and project ID', () {
      expect(
        BrowserbaseProvider(apiKey: 'key', projectId: null).isAvailable,
        isFalse,
      );
      expect(
        BrowserbaseProvider(apiKey: null, projectId: 'proj').isAvailable,
        isFalse,
      );
      expect(
        BrowserbaseProvider(apiKey: 'key', projectId: 'proj').isAvailable,
        isTrue,
      );
    });
  });

  group('BrowserlessProvider', () {
    test('has correct name', () {
      final provider = BrowserlessProvider(
        apiKey: 'key',
        baseUrl: 'https://chrome.example.com',
      );
      expect(provider.name, 'browserless');
    });

    test('is available with API key', () {
      final provider = BrowserlessProvider(
        apiKey: 'key',
        baseUrl: 'https://chrome.example.com',
      );
      expect(provider.isAvailable, isTrue);
    });

    test('builds WebSocket URL from base URL', () {
      final provider = BrowserlessProvider(
        apiKey: 'my-key',
        baseUrl: 'https://chrome.browserless.io',
      );
      final wsUrl = provider.buildWsUrl();
      expect(wsUrl, contains('wss://'));
      expect(wsUrl, contains('my-key'));
    });
  });
}
```

**Step 2: Implement Steel provider**

Create `cli/lib/src/web/browser/providers/steel_provider.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:glue/src/web/browser/browser_endpoint.dart';

/// Steel.dev cloud browser provider.
///
/// Creates browser sessions via the Steel API and returns
/// CDP WebSocket URLs for puppeteer connection.
class SteelProvider implements BrowserEndpointProvider {
  final String? apiKey;
  static const _baseUrl = 'https://api.steel.dev/v1';

  SteelProvider({required this.apiKey});

  @override
  String get name => 'steel';

  @override
  bool get isAvailable => apiKey != null && apiKey!.isNotEmpty;

  @override
  Future<BrowserEndpoint> provision() async {
    if (!isAvailable) throw StateError('Steel API key not configured');

    final response = await http
        .post(
          Uri.parse('$_baseUrl/sessions'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'projectId': 'default'}),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(
        'Steel API error ${response.statusCode}: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final sessionId = json['id'] as String;
    final wsUrl = json['websocketUrl'] as String;
    final viewUrl = json['viewerUrl'] as String?;

    return BrowserEndpoint(
      cdpWsUrl: wsUrl,
      backendName: name,
      viewUrl: viewUrl ?? 'https://app.steel.dev/sessions/$sessionId',
      onClose: () async {
        try {
          await http.delete(
            Uri.parse('$_baseUrl/sessions/$sessionId'),
            headers: {'Authorization': 'Bearer $apiKey'},
          );
        } catch (_) {}
      },
    );
  }
}
```

**Step 3: Implement Browserbase provider**

Create `cli/lib/src/web/browser/providers/browserbase_provider.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:glue/src/web/browser/browser_endpoint.dart';

/// Browserbase cloud browser provider.
///
/// Creates browser sessions via the Browserbase API.
class BrowserbaseProvider implements BrowserEndpointProvider {
  final String? apiKey;
  final String? projectId;
  static const _baseUrl = 'https://www.browserbase.com/v1';

  BrowserbaseProvider({required this.apiKey, required this.projectId});

  @override
  String get name => 'browserbase';

  @override
  bool get isAvailable =>
      apiKey != null &&
      apiKey!.isNotEmpty &&
      projectId != null &&
      projectId!.isNotEmpty;

  @override
  Future<BrowserEndpoint> provision() async {
    if (!isAvailable) {
      throw StateError('Browserbase API key or project ID not configured');
    }

    final response = await http
        .post(
          Uri.parse('$_baseUrl/sessions'),
          headers: {
            'X-BB-API-Key': apiKey!,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'projectId': projectId}),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(
        'Browserbase API error ${response.statusCode}: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final sessionId = json['id'] as String;
    final wsUrl =
        'wss://connect.browserbase.com?apiKey=$apiKey&sessionId=$sessionId';

    return BrowserEndpoint(
      cdpWsUrl: wsUrl,
      backendName: name,
      viewUrl: 'https://www.browserbase.com/sessions/$sessionId',
      onClose: () async {
        try {
          await http.post(
            Uri.parse('$_baseUrl/sessions/$sessionId/stop'),
            headers: {'X-BB-API-Key': apiKey!},
          );
        } catch (_) {}
      },
    );
  }
}
```

**Step 4: Implement Browserless provider**

Create `cli/lib/src/web/browser/providers/browserless_provider.dart`:

```dart
import 'dart:async';

import 'package:glue/src/web/browser/browser_endpoint.dart';

/// Browserless.io cloud browser provider.
///
/// Connects to a Browserless instance (cloud or self-hosted).
/// WebSocket URL format: wss://<host>?token=<api_key>
class BrowserlessProvider implements BrowserEndpointProvider {
  final String? apiKey;
  final String baseUrl;

  BrowserlessProvider({required this.apiKey, required this.baseUrl});

  @override
  String get name => 'browserless';

  @override
  bool get isAvailable => apiKey != null && apiKey!.isNotEmpty;

  /// Build the WebSocket URL for CDP connection.
  String buildWsUrl() {
    var wsBase = baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    if (!wsBase.startsWith('ws')) {
      wsBase = 'wss://$wsBase';
    }
    return '$wsBase?token=$apiKey';
  }

  @override
  Future<BrowserEndpoint> provision() async {
    if (!isAvailable) {
      throw StateError('Browserless API key not configured');
    }

    final wsUrl = buildWsUrl();

    return BrowserEndpoint(
      cdpWsUrl: wsUrl,
      backendName: name,
      // Browserless doesn't have a session viewer URL by default.
    );
  }
}
```

**Step 5: Run tests**

Run: `cd cli && dart test test/web/browser/providers/cloud_providers_test.dart`
Expected: all pass

**Step 6: Commit**

```bash
git add cli/lib/src/web/browser/providers/
git add cli/test/web/browser/providers/cloud_providers_test.dart
git commit -m "feat(browser): add Steel, Browserbase, and Browserless providers"
```

---

### Task 13: `DockerBrowserProvider` decorator

**Files:**
- Create: `cli/lib/src/web/browser/providers/docker_browser_provider.dart`
- Test: `cli/test/web/browser/providers/docker_browser_provider_test.dart`

**Step 1: Write tests**

Create `cli/test/web/browser/providers/docker_browser_provider_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:glue/src/web/browser/providers/docker_browser_provider.dart';

void main() {
  group('DockerBrowserProvider', () {
    test('has correct name', () {
      final provider = DockerBrowserProvider(
        image: 'browserless/chrome:latest',
        port: 3000,
        sessionId: 'test-session',
      );
      expect(provider.name, 'docker');
    });

    test('is always available', () {
      final provider = DockerBrowserProvider(
        image: 'browserless/chrome:latest',
        port: 3000,
        sessionId: 'test-session',
      );
      expect(provider.isAvailable, isTrue);
    });

    test('builds docker run args correctly', () {
      final provider = DockerBrowserProvider(
        image: 'browserless/chrome:latest',
        port: 3000,
        sessionId: 'abc-123',
      );
      final args = provider.buildDockerRunArgs();
      expect(args, contains('--label'));
      expect(args, contains('glue.session=abc-123'));
      expect(args, contains('-p'));
      expect(args.any((a) => a.contains(':3000')), isTrue);
      expect(args, contains('browserless/chrome:latest'));
    });

    test('computes WebSocket URL from port', () {
      final provider = DockerBrowserProvider(
        image: 'browserless/chrome:latest',
        port: 3000,
        sessionId: 'test',
      );
      final wsUrl = provider.buildWsUrl(3000);
      expect(wsUrl, 'ws://localhost:3000');
    });
  });
}
```

**Step 2: Implement**

Create `cli/lib/src/web/browser/providers/docker_browser_provider.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:glue/src/web/browser/browser_endpoint.dart';

/// Docker-based browser provider.
///
/// Runs a Browserless/Chrome container with Docker, labels it with the
/// session ID for cleanup, and returns a CDP WebSocket URL.
class DockerBrowserProvider implements BrowserEndpointProvider {
  final String image;
  final int port;
  final String sessionId;
  final bool headed;

  String? _containerId;

  DockerBrowserProvider({
    required this.image,
    required this.port,
    required this.sessionId,
    this.headed = false,
  });

  @override
  String get name => 'docker';

  @override
  bool get isAvailable => true;

  /// Build the WebSocket URL for a given port.
  String buildWsUrl(int port) => 'ws://localhost:$port';

  /// Build Docker run arguments.
  List<String> buildDockerRunArgs() {
    return [
      'run',
      '-d',
      '--rm',
      '--label', 'glue.session=$sessionId',
      '--label', 'glue.component=browser',
      '-p', '0:$port',
      image,
    ];
  }

  @override
  Future<BrowserEndpoint> provision() async {
    // Check Docker availability.
    try {
      final versionResult = await Process.run('docker', ['version', '--format', '{{.Server.Version}}']);
      if (versionResult.exitCode != 0) {
        throw StateError('Docker is not available');
      }
    } catch (e) {
      throw StateError('Docker is not available: $e');
    }

    // Start the container with an ephemeral host port.
    final runResult = await Process.run('docker', buildDockerRunArgs());
    if (runResult.exitCode != 0) {
      throw StateError(
        'Failed to start browser container: ${runResult.stderr}',
      );
    }

    _containerId = (runResult.stdout as String).trim();

    // Get the mapped host port.
    final portResult = await Process.run('docker', [
      'port', _containerId!, '$port/tcp',
    ]);
    if (portResult.exitCode != 0) {
      await _cleanup();
      throw StateError('Failed to get container port mapping');
    }

    final portOutput = (portResult.stdout as String).trim();
    // Format: 0.0.0.0:12345 or :::12345
    final hostPort = int.parse(portOutput.split(':').last);

    // Wait for the browser to become ready.
    await _waitForReady(hostPort);

    return BrowserEndpoint(
      cdpWsUrl: buildWsUrl(hostPort),
      backendName: name,
      headed: headed,
      onClose: _cleanup,
    );
  }

  Future<void> _waitForReady(int hostPort, {int maxAttempts = 30}) async {
    for (var i = 0; i < maxAttempts; i++) {
      try {
        final socket = await Socket.connect('localhost', hostPort,
            timeout: const Duration(seconds: 1));
        await socket.close();
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    throw StateError('Browser container did not become ready in time');
  }

  Future<void> _cleanup() async {
    if (_containerId == null) return;
    try {
      await Process.run('docker', ['stop', '-t', '5', _containerId!]);
    } catch (_) {}
    _containerId = null;
  }

  /// Cleanup stale containers from previous sessions.
  ///
  /// Finds containers with `glue.component=browser` label and stops them.
  /// Called on app startup for crash recovery.
  static Future<void> cleanupStaleContainers() async {
    try {
      final result = await Process.run('docker', [
        'ps', '-q', '--filter', 'label=glue.component=browser',
      ]);
      if (result.exitCode != 0) return;

      final ids = (result.stdout as String)
          .trim()
          .split('\n')
          .where((id) => id.isNotEmpty)
          .toList();

      for (final id in ids) {
        await Process.run('docker', ['stop', '-t', '5', id]);
      }
    } catch (_) {}
  }
}
```

**Step 3: Run tests**

Run: `cd cli && dart test test/web/browser/providers/docker_browser_provider_test.dart`
Expected: all pass

**Step 4: Commit**

```bash
git add cli/lib/src/web/browser/providers/docker_browser_provider.dart cli/test/web/browser/providers/docker_browser_provider_test.dart
git commit -m "feat(browser): add DockerBrowserProvider with session labeling and cleanup"
```

---

### Task 14: `BrowserManager` (session-scoped lifecycle)

**Files:**
- Create: `cli/lib/src/web/browser/browser_manager.dart`
- Test: `cli/test/web/browser/browser_manager_test.dart`

**Step 1: Write tests**

Create `cli/test/web/browser/browser_manager_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:glue/src/web/browser/browser_manager.dart';
import 'package:glue/src/web/browser/browser_endpoint.dart';
import 'package:glue/src/web/browser/browser_config.dart';

class _MockProvider implements BrowserEndpointProvider {
  bool provisioned = false;
  bool closed = false;
  int provisionCount = 0;

  @override
  String get name => 'mock';

  @override
  bool get isAvailable => true;

  @override
  Future<BrowserEndpoint> provision() async {
    provisioned = true;
    provisionCount++;
    return BrowserEndpoint(
      cdpWsUrl: 'ws://localhost:9222/devtools/browser/mock',
      backendName: 'mock',
      onClose: () async {
        closed = true;
      },
    );
  }
}

void main() {
  group('BrowserManager', () {
    late BrowserManager manager;
    late _MockProvider provider;

    setUp(() {
      provider = _MockProvider();
      manager = BrowserManager(provider: provider);
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('is not connected initially', () {
      expect(manager.isConnected, isFalse);
    });

    test('provisions on first getEndpoint call', () async {
      final endpoint = await manager.getEndpoint();
      expect(endpoint, isNotNull);
      expect(provider.provisioned, isTrue);
      expect(manager.isConnected, isTrue);
    });

    test('reuses endpoint on subsequent calls', () async {
      final first = await manager.getEndpoint();
      final second = await manager.getEndpoint();
      expect(identical(first, second), isTrue);
      expect(provider.provisionCount, 1);
    });

    test('dispose closes endpoint', () async {
      await manager.getEndpoint();
      await manager.dispose();
      expect(provider.closed, isTrue);
      expect(manager.isConnected, isFalse);
    });

    test('can reconnect after dispose', () async {
      await manager.getEndpoint();
      await manager.dispose();
      expect(manager.isConnected, isFalse);

      final endpoint = await manager.getEndpoint();
      expect(endpoint, isNotNull);
      expect(provider.provisionCount, 2);
    });
  });
}
```

**Step 2: Implement**

Create `cli/lib/src/web/browser/browser_manager.dart`:

```dart
import 'package:glue/src/web/browser/browser_endpoint.dart';

/// Session-scoped browser lifecycle manager.
///
/// Lazily provisions a browser endpoint on first use and reuses it
/// across tool calls within the same session. Disposes on session end.
class BrowserManager {
  final BrowserEndpointProvider provider;
  BrowserEndpoint? _endpoint;

  BrowserManager({required this.provider});

  /// Whether a browser endpoint is currently active.
  bool get isConnected => _endpoint != null;

  /// Get or provision a browser endpoint.
  ///
  /// First call provisions the browser; subsequent calls reuse it.
  Future<BrowserEndpoint> getEndpoint() async {
    if (_endpoint != null) return _endpoint!;
    _endpoint = await provider.provision();
    return _endpoint!;
  }

  /// Close the browser endpoint and release resources.
  Future<void> dispose() async {
    if (_endpoint != null) {
      await _endpoint!.close();
      _endpoint = null;
    }
  }
}
```

**Step 3: Run tests**

Run: `cd cli && dart test test/web/browser/browser_manager_test.dart`
Expected: all pass

**Step 4: Commit**

```bash
git add cli/lib/src/web/browser/browser_manager.dart cli/test/web/browser/browser_manager_test.dart
git commit -m "feat(browser): add BrowserManager for session-scoped lifecycle"
```

---

### Task 15: `BrowserTool` (Tool wrapper)

**Files:**
- Create: `cli/lib/src/tools/web_browser_tool.dart`
- Test: `cli/test/tools/web_browser_tool_test.dart`

**Step 1: Write tests**

Create `cli/test/tools/web_browser_tool_test.dart`:

```dart
import 'package:test/test.dart';
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
      final result = await tool.execute({});
      expect(result, contains('Error'));
    });

    test('returns error for invalid action', () async {
      final result = await tool.execute({'action': 'invalid'});
      expect(result, contains('Error'));
      expect(result, contains('invalid'));
    });

    test('navigate requires url', () async {
      final result = await tool.execute({'action': 'navigate'});
      expect(result, contains('Error'));
      expect(result, contains('url'));
    });

    test('click requires selector', () async {
      final result = await tool.execute({'action': 'click'});
      expect(result, contains('Error'));
      expect(result, contains('selector'));
    });
  });
}
```

**Step 2: Implement**

Create `cli/lib/src/tools/web_browser_tool.dart`:

```dart
import 'dart:convert';

import 'package:puppeteer/puppeteer.dart' as pptr;

import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/web/browser/browser_manager.dart';
import 'package:glue/src/web/fetch/html_extractor.dart';
import 'package:glue/src/web/fetch/html_to_markdown.dart';
import 'package:glue/src/web/fetch/truncation.dart';

/// Tool for browser-based web interaction via Chrome DevTools Protocol.
///
/// Supports navigation, screenshots, clicking, text extraction, and
/// JavaScript evaluation. Uses a session-scoped browser managed by
/// [BrowserManager].
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
  Future<String> execute(Map<String, dynamic> args) async {
    final action = args['action'];
    if (action is! String || action.isEmpty) {
      return 'Error: no action provided. '
          'Valid actions: ${_validActions.join(", ")}';
    }
    if (!_validActions.contains(action)) {
      return 'Error: invalid action "$action". '
          'Valid actions: ${_validActions.join(", ")}';
    }

    try {
      return await _dispatch(action, args);
    } catch (e) {
      return 'Error: $e';
    }
  }

  Future<String> _dispatch(String action, Map<String, dynamic> args) async {
    return switch (action) {
      'navigate' => _navigate(args),
      'screenshot' => _screenshot(args),
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

  Future<String> _screenshot(Map<String, dynamic> args) async {
    final page = await _ensurePage();
    final selector = args['selector'] as String?;

    List<int> bytes;
    if (selector != null && selector.isNotEmpty) {
      final element = await page.$(selector);
      bytes = await element.screenshot();
    } else {
      bytes = await page.screenshot();
    }

    final base64Img = base64Encode(bytes);
    return 'Screenshot captured (${bytes.length} bytes).\n'
        'Base64: data:image/png;base64,$base64Img';
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
```

**Step 3: Run tests**

Run: `cd cli && dart test test/tools/web_browser_tool_test.dart`
Expected: all pass

**Step 4: Commit**

```bash
git add cli/lib/src/tools/web_browser_tool.dart cli/test/tools/web_browser_tool_test.dart
git commit -m "feat(browser): add WebBrowserTool with navigate/screenshot/click/type/extract/evaluate"
```

---

### Task 16: Wire `BrowserTool` into `App`

**Files:**
- Modify: `cli/lib/src/app.dart`

**Step 1: Add imports**

Add to the imports in `cli/lib/src/app.dart`:

```dart
import 'package:glue/src/tools/web_browser_tool.dart';
import 'package:glue/src/web/browser/browser_manager.dart';
import 'package:glue/src/web/browser/browser_config.dart';
import 'package:glue/src/web/browser/providers/local_provider.dart';
import 'package:glue/src/web/browser/providers/docker_browser_provider.dart';
import 'package:glue/src/web/browser/providers/steel_provider.dart';
import 'package:glue/src/web/browser/providers/browserbase_provider.dart';
import 'package:glue/src/web/browser/providers/browserless_provider.dart';
```

**Step 2: Create browser provider factory**

In the `App.create()` method, after the search router and tools map setup, add browser provider creation and tool registration. Add this code after `'web_search': WebSearchTool(searchRouter),` in the tools map:

```dart
    // Create browser provider based on config.
    final browserProvider = switch (config.webConfig.browser.backend) {
      BrowserBackend.local => LocalProvider(config.webConfig.browser),
      BrowserBackend.docker => DockerBrowserProvider(
          image: config.webConfig.browser.dockerImage,
          port: config.webConfig.browser.dockerPort,
          sessionId: sessionId,
        ),
      BrowserBackend.steel => SteelProvider(
          apiKey: config.webConfig.browser.steelApiKey,
        ),
      BrowserBackend.browserbase => BrowserbaseProvider(
          apiKey: config.webConfig.browser.browserbaseApiKey,
          projectId: config.webConfig.browser.browserbaseProjectId,
        ),
      BrowserBackend.browserless => BrowserlessProvider(
          apiKey: config.webConfig.browser.browserlessApiKey,
          baseUrl: config.webConfig.browser.browserlessBaseUrl ?? '',
        ),
    };
    final browserManager = BrowserManager(provider: browserProvider);
```

Then add to the tools map:

```dart
      'web_browser': WebBrowserTool(browserManager),
```

**Step 3: Add `web_browser` to auto-approved tools**

In the `_autoApprovedTools` set:

```dart
    'web_browser',
```

**Step 4: Add browser cleanup on exit**

In the `requestExit()` or cleanup method of `App`, add:

```dart
    await browserManager.dispose();
```

Alternatively, since `browserManager` is created inside `App.create()`, it should be stored as a field. Add a `BrowserManager?` field to `App`:

```dart
  final BrowserManager? _browserManager;
```

And pass it through the constructor, then dispose in the exit path.

**Step 5: Verify**

Run: `cd cli && dart analyze`
Expected: no warnings

**Step 6: Commit**

```bash
git add cli/lib/src/app.dart
git commit -m "feat(browser): wire WebBrowserTool into App with provider factory"
```

---

### Task 17: Docker cleanup + `SessionState` integration

**Files:**
- Modify: `cli/lib/src/storage/session_state.dart`
- Modify: `cli/lib/src/app.dart` (startup cleanup)

**Step 1: Add browser container tracking to `SessionState`**

Modify `cli/lib/src/storage/session_state.dart` to track browser container IDs:

```dart
class SessionState {
  final String _dir;
  final List<MountEntry> _dockerMounts = [];
  final List<String> _browserContainerIds = [];

  SessionState._(this._dir);

  List<MountEntry> get dockerMounts => List.unmodifiable(_dockerMounts);
  List<String> get browserContainerIds =>
      List.unmodifiable(_browserContainerIds);
```

Add load/save support for the browser container IDs in the `SessionState.load()` factory:

After the `docker.mounts` loading block, add:

```dart
        final browserIds = json['browser']?['container_ids'] as List?;
        if (browserIds != null) {
          for (final id in browserIds) {
            state._browserContainerIds.add(id as String);
          }
        }
```

Add mutation methods:

```dart
  void addBrowserContainerId(String containerId) {
    if (!_browserContainerIds.contains(containerId)) {
      _browserContainerIds.add(containerId);
      _persist();
    }
  }

  void removeBrowserContainerId(String containerId) {
    _browserContainerIds.remove(containerId);
    _persist();
  }
```

Update `_persist()` to include browser container IDs:

```dart
  void _persist() {
    final file = File(p.join(_dir, 'state.json'));
    file.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    file.writeAsStringSync(encoder.convert({
      'version': 1,
      'docker': {
        'mounts': _dockerMounts.map((m) => m.toJson()).toList(),
      },
      'browser': {
        'container_ids': _browserContainerIds,
      },
    }));
  }
```

**Step 2: Add startup cleanup in `App.create()`**

In `App.create()`, before creating the browser provider, add:

```dart
    // Cleanup stale browser containers from crashed sessions.
    await DockerBrowserProvider.cleanupStaleContainers();
```

**Step 3: Verify**

Run: `cd cli && dart analyze`
Expected: no warnings

Run: `cd cli && dart test`
Expected: all pass

**Step 4: Commit**

```bash
git add cli/lib/src/storage/session_state.dart cli/lib/src/app.dart
git commit -m "feat(browser): add browser container tracking and crash recovery cleanup"
```

---

## Phase 3: Integration Testing

### Task 18: E2E test for PDF extraction

**Files:**
- Create: `cli/test/web/fetch/pdf_integration_test.dart`

**Step 1: Write integration test**

Create `cli/test/web/fetch/pdf_integration_test.dart`:

```dart
@Tags(['e2e'])
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:glue/src/web/fetch/pdf_text_extractor.dart';

void main() {
  group('PDF extraction integration', () {
    test('pdftotext availability check', () async {
      final available = await PdfTextExtractor.checkPdftotextAvailable();
      // This test just verifies the check doesn't crash.
      // Actual availability depends on the host system.
      expect(available, isA<bool>());
    },
        skip: 'Requires pdftotext installed (apt install poppler-utils / '
            'brew install poppler)');
  });
}
```

**Step 2: Commit**

```bash
git add cli/test/web/fetch/pdf_integration_test.dart
git commit -m "test(pdf): add integration test scaffold for PDF extraction"
```

---

### Task 19: E2E test for browser tool

**Files:**
- Create: `cli/test/web/browser/browser_integration_test.dart`

**Step 1: Write integration test**

Create `cli/test/web/browser/browser_integration_test.dart`:

```dart
@Tags(['e2e'])
import 'package:test/test.dart';
import 'package:glue/src/web/browser/browser_manager.dart';
import 'package:glue/src/web/browser/browser_config.dart';
import 'package:glue/src/web/browser/providers/local_provider.dart';
import 'package:glue/src/tools/web_browser_tool.dart';

void main() {
  group('WebBrowserTool integration', () {
    late BrowserManager manager;
    late WebBrowserTool tool;

    setUp(() {
      manager = BrowserManager(
        provider: LocalProvider(const BrowserConfig()),
      );
      tool = WebBrowserTool(manager);
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('navigate to a page and extract text', () async {
      final navResult = await tool.execute({
        'action': 'navigate',
        'url': 'https://example.com',
      });
      expect(navResult, contains('Navigated to'));
      expect(navResult, contains('Example Domain'));

      final textResult = await tool.execute({
        'action': 'extract_text',
      });
      expect(textResult, contains('Example Domain'));
    });

    test('evaluate JavaScript', () async {
      await tool.execute({
        'action': 'navigate',
        'url': 'https://example.com',
      });

      final result = await tool.execute({
        'action': 'evaluate',
        'javascript': 'document.title',
      });
      expect(result, contains('Example Domain'));
    });

    test('take screenshot', () async {
      await tool.execute({
        'action': 'navigate',
        'url': 'https://example.com',
      });

      final result = await tool.execute({
        'action': 'screenshot',
      });
      expect(result, contains('Screenshot captured'));
      expect(result, contains('base64'));
    });
  },
      skip: 'Requires Chrome/Chromium installed. '
          'Run with: dart test --run-skipped -t e2e');
}
```

**Step 2: Commit**

```bash
git add cli/test/web/browser/browser_integration_test.dart
git commit -m "test(browser): add integration test scaffold for browser tool"
```

---

## Summary

### New files created

```
cli/lib/src/web/fetch/pdf_text_extractor.dart
cli/lib/src/web/fetch/ocr_client.dart
cli/lib/src/web/browser/browser_config.dart
cli/lib/src/web/browser/browser_endpoint.dart
cli/lib/src/web/browser/browser_manager.dart
cli/lib/src/web/browser/providers/local_provider.dart
cli/lib/src/web/browser/providers/docker_browser_provider.dart
cli/lib/src/web/browser/providers/steel_provider.dart
cli/lib/src/web/browser/providers/browserbase_provider.dart
cli/lib/src/web/browser/providers/browserless_provider.dart
cli/lib/src/tools/web_browser_tool.dart
cli/test/web/fetch/pdf_text_extractor_test.dart
cli/test/web/fetch/ocr_client_test.dart
cli/test/web/fetch/pdf_integration_test.dart
cli/test/web/browser/browser_config_test.dart
cli/test/web/browser/browser_endpoint_test.dart
cli/test/web/browser/browser_manager_test.dart
cli/test/web/browser/providers/local_provider_test.dart
cli/test/web/browser/providers/cloud_providers_test.dart
cli/test/web/browser/providers/docker_browser_provider_test.dart
cli/test/web/browser/browser_integration_test.dart
cli/test/tools/web_browser_tool_test.dart
```

### Existing files modified

```
cli/pubspec.yaml (add puppeteer dependency)
cli/lib/src/config/constants.dart (PDF + browser constants)
cli/lib/src/web/web_config.dart (PdfConfig, BrowserConfig, WebConfig fields)
cli/lib/src/config/glue_config.dart (PDF + browser config resolution)
cli/lib/src/web/fetch/web_fetch_client.dart (PDF pipeline stage)
cli/lib/src/tools/web_fetch_tool.dart (PdfConfig param, updated description)
cli/lib/src/app.dart (browser provider factory, tool registration, cleanup)
cli/lib/src/storage/session_state.dart (browser container tracking)
cli/test/web/web_config_test.dart (PdfConfig tests)
cli/test/web/fetch/web_fetch_client_test.dart (PDF detection tests)
```

### Config reference

```yaml
# ~/.glue/config.yaml
web:
  fetch:
    timeout_seconds: 30
    max_bytes: 5242880
    allow_jina_fallback: true
    jina_api_key: "..."

  search:
    provider: brave
    brave_api_key: "..."
    tavily_api_key: "..."
    firecrawl_api_key: "..."

  pdf:
    max_bytes: 20971520
    timeout_seconds: 60
    enable_ocr_fallback: true
    ocr_provider: mistral  # mistral | openai
    mistral_api_key: "..."
    openai_api_key: "..."

  browser:
    backend: local  # local | docker | steel | browserbase | browserless
    headed: false
    docker:
      image: browserless/chrome:latest
      port: 3000
    steel:
      api_key: "..."
    browserbase:
      api_key: "..."
      project_id: "..."
    browserless:
      base_url: "https://..."
      api_key: "..."
```

### Environment variables

```
MISTRAL_API_KEY        — Mistral OCR API key
GLUE_OCR_PROVIDER      — OCR provider override (mistral | openai)
GLUE_BROWSER_BACKEND   — Browser backend override
STEEL_API_KEY          — Steel.dev API key
BROWSERBASE_API_KEY    — Browserbase API key
BROWSERBASE_PROJECT_ID — Browserbase project ID
BROWSERLESS_API_KEY    — Browserless.io API key
```
