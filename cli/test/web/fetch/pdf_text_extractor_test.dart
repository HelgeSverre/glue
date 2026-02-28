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

    test('extract handles process with large stderr without deadlock',
        () async {
      // Verify the extractor doesn't deadlock when stderr is consumed
      // concurrently with exitCode. We test this by running extraction
      // on garbage input that should produce stderr output.
      final available = await PdfTextExtractor.checkPdftotextAvailable();
      if (!available) {
        // Skip on systems without pdftotext.
        return;
      }

      final extractor = PdfTextExtractor(timeoutSeconds: 10);
      // Not a valid PDF — pdftotext will write to stderr and fail.
      final result = await extractor.extract(
        Uint8List.fromList('not a real pdf file at all'.codeUnits),
      );
      // Should return an error, not deadlock or timeout.
      expect(result.isSuccess, isFalse);
    });

    test('extract kills process on timeout', () async {
      // Use an extremely short timeout to verify kill behavior.
      final extractor = PdfTextExtractor(timeoutSeconds: 0);

      // Create a minimal valid-looking PDF to start pdftotext.
      final result = await extractor.extract(
        Uint8List.fromList('%PDF-1.4 fake'.codeUnits),
      );

      // Should timeout, not hang forever.
      expect(result.isSuccess, isFalse);
      expect(result.error, contains('timed out'));
    });
  });
}
