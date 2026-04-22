import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('share planning docs and prototype exist', () {
    expect(File('docs/plans/share-command.md').existsSync(), isTrue);
    expect(File('docs/prototypes/share-conversation.html').existsSync(), isTrue);
  });
}
