import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:glue/src/utils.dart';

/// Result of PDF text extraction.
class PdfExtractionResult {
  final String? text;
  final String? error;
  final int pageCount;

  PdfExtractionResult({this.text, this.error, this.pageCount = 0});

  bool get isSuccess =>
      text != null && text!.trim().isNotEmpty && error == null;

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
  Future<PdfExtractionResult> extract(Uint8List bytes) async {
    final tempDir = await Directory.systemTemp.createTemp('glue-pdf-');
    final inputFile = File(p.join(tempDir.path, 'input.pdf'));
    final outputFile = File(p.join(tempDir.path, 'output.txt'));

    Process? process;
    try {
      await inputFile.writeAsBytes(bytes);

      process = await Process.start(
        'pdftotext',
        ['-layout', inputFile.path, outputFile.path],
      );

      // Consume stderr concurrently with exitCode to avoid deadlock
      // when pdftotext fills the pipe buffer.
      final results = await Future.wait([
        process.exitCode,
        process.stderr.transform(const SystemEncoding().decoder).join(),
      ]).timeout(timeoutSeconds.seconds);

      final exitCode = results[0] as int;
      final stderr = results[1] as String;

      if (exitCode != 0) {
        return PdfExtractionResult.withError(
          'pdftotext failed (exit $exitCode): ${stderr.trim()}',
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
      process?.kill();
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
