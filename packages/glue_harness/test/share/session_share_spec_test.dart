import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('share planning docs and production html assets exist', () {
    // Resolve paths relative to the repo root so the test works regardless of
    // whether `dart test` was launched from packages/glue_harness/ (the usual
    // case) or from the repo root.
    // The plan moves to docs/plans/done/ once shipped. Accept either path.
    final candidatePlanPaths = [
      'docs/plans/2026-04-22-share-command.md',
      'docs/plans/done/2026-04-22-share-command.md',
      '../../docs/plans/2026-04-22-share-command.md',
      '../../docs/plans/done/2026-04-22-share-command.md',
    ];
    final planExists = candidatePlanPaths.any(
      (path) => File(path).existsSync(),
    );
    expect(
      planExists,
      isTrue,
      reason: 'expected one of: ${candidatePlanPaths.join(', ')}',
    );

    final candidateTemplatePaths = [
      'lib/src/share/html/share_page_template.html',
      'packages/glue_harness/lib/src/share/html/share_page_template.html',
    ];
    expect(candidateTemplatePaths.any((p) => File(p).existsSync()), isTrue);

    final candidateCssPaths = [
      'lib/src/share/html/share_page.css',
      'packages/glue_harness/lib/src/share/html/share_page.css',
    ];
    expect(candidateCssPaths.any((p) => File(p).existsSync()), isTrue);
  });
}
