/// Formatter for `glue trace export` — one-line success plus a hint.
library;

import 'package:glue/src/commands/trace_command.dart';
import 'package:glue/src/terminal/brand.dart';
import 'package:glue/src/terminal/tty_style.dart';

String formatTraceExportResult(TraceExportResult result, {bool? ansiEnabled}) {
  final ansi = ansiEnabled ?? stdoutSupportsAnsi();
  final lines = <String>[
    '$markerOk Wrote trace: ${styledOrPlain(result.outputPath, (s) => s.bold, ansiEnabled: ansi)}',
    styledOrPlain(
      '  ${result.spanCount} span${result.spanCount == 1 ? '' : 's'}'
      '${result.droppedInFlight > 0 ? ', ${result.droppedInFlight} dropped (in-flight)' : ''}'
      ', ${result.scannedLogFiles.length} log file${result.scannedLogFiles.length == 1 ? '' : 's'} scanned',
      (s) => s.gray,
      ansiEnabled: ansi,
    ),
    styledOrPlain(
      '  Open https://profiler.firefox.com and drop the file in.',
      (s) => s.gray,
      ansiEnabled: ansi,
    ),
  ];
  return lines.join('\n');
}
