import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('share planning docs and production html assets exist', () {
    final planExists = [
      'docs/plans/2026-04-22-share-command.md',
      '../docs/plans/2026-04-22-share-command.md',
    ].any((path) => File(path).existsSync());
    expect(planExists, isTrue);
    // Assets moved to packages/glue_harness/ in the harness extraction.
    expect(
      File('../packages/glue_harness/lib/src/share/html/'
              'share_page_template.html')
          .existsSync(),
      isTrue,
    );
    expect(
      File('../packages/glue_harness/lib/src/share/html/share_page.css')
          .existsSync(),
      isTrue,
    );
  });
}
