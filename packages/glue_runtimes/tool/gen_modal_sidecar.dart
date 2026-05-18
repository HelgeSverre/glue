/// Embeds `lib/src/modal/modal_sidecar.py` as a Dart string constant
/// at `lib/src/modal/sidecar_source.g.dart` so the script ships
/// inside glue's AOT-compiled binary (no external file dependency).
///
/// Re-run after editing the sidecar: `dart run tool/gen_modal_sidecar.dart`.
/// `just glue_runtimes::gen-check` will catch out-of-date generated
/// output.
library;

import 'dart:io';

void main() {
  final src = File('lib/src/modal/modal_sidecar.py').readAsStringSync();
  // Raw triple-quoted string preserves the python verbatim (including
  // backslashes / dollar signs) so no escaping is required.
  final out = StringBuffer()
    ..writeln('// GENERATED — do not edit. Run:')
    ..writeln('//   dart run tool/gen_modal_sidecar.dart')
    ..writeln('// from packages/glue_runtimes/ after editing')
    ..writeln('// lib/src/modal/modal_sidecar.py')
    ..writeln()
    // Use single-quoted raw triple-string — the python uses `"""`
    // docstrings which would terminate r"""..."""; it uses no `'''`.
    ..writeln("const String modalSidecarSource = r'''")
    ..write(src)
    ..writeln("''';");
  File('lib/src/modal/sidecar_source.g.dart')
      .writeAsStringSync(out.toString());
  stdout.writeln('wrote lib/src/modal/sidecar_source.g.dart (${src.length} chars)');
}
