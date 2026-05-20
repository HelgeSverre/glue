import 'dart:io';

import 'package:test/test.dart';

import 'package:glue_runtimes/src/modal/sidecar_source.g.dart';

void main() {
  test(
      'sidecar_source.g.dart matches modal_sidecar.py — re-run '
      '`dart run tool/gen_modal_sidecar.dart` to regenerate', () {
    final source = File('lib/src/modal/modal_sidecar.py').readAsStringSync();
    // The constant should hold the .py byte-for-byte (after the raw
    // triple-string wrapper). Cheapest comparison: assert the .py is
    // a substring of the embedded constant.
    expect(modalSidecarSource, equals(source));
  });
}
