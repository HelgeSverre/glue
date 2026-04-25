import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('share production html assets exist', () {
    expect(
      File('lib/src/share/html/share_page_template.html').existsSync(),
      isTrue,
    );
    expect(
      File('lib/src/share/html/share_page.css').existsSync(),
      isTrue,
    );
  });
}
