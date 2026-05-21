import 'package:glue_harness/glue_harness.dart';
import 'package:test/test.dart';

void main() {
  test(
    'ShareHtmlAssetsLoader resolves the share html assets from source tree',
    () {
      const loader = ShareHtmlAssetsLoader();

      final template = loader.loadTemplate();
      final stylesheet = loader.loadStylesheet();

      expect(template, contains('<!DOCTYPE html>'));
      expect(template, contains('{{page_title}}'));
      expect(template, contains('{{transcript_entries}}'));
      expect(stylesheet, contains('.share-header'));
      expect(stylesheet, contains('.share-meta'));
    },
  );
}
