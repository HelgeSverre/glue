import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:glue/src/commands/trace_export_format.dart';
import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:path/path.dart' as p;

/// Outcome of `glue trace export`. Returned by [exportSessionTrace] so the
/// `Command<int>` layer can render it via [formatTraceExportResult] without
/// owning any I/O logic itself.
class TraceExportResult {
  const TraceExportResult({
    required this.sessionId,
    required this.outputPath,
    required this.spanCount,
    required this.droppedInFlight,
    required this.scannedLogFiles,
  });

  final String sessionId;
  final String outputPath;

  /// Number of completed spans written as Complete (`X`) events. Excludes
  /// per-span Instant child events and `M` metadata events.
  final int spanCount;

  /// Spans that fell within the session window but had no `end_time` — they
  /// were in flight when the log was sampled and cannot be Complete events.
  final int droppedInFlight;

  /// `spans-*.jsonl` files whose date range overlapped the session window.
  /// Empty when the session left no spans on disk (e.g. early crash before
  /// the file sink wrote anything).
  final List<String> scannedLogFiles;
}

class TraceExportException implements Exception {
  TraceExportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Resolves [sessionId] to a session on disk, scans `logsDir` for spans
/// that fall within the session window, converts them with
/// [spansToChromeTrace], and writes the result to [outputPath] (defaulting
/// to `<sessionDir>/trace.json`).
///
/// Time-range filtering — rather than per-span `session.id` matching —
/// keeps this command zero-cost: it reads existing JSONL without any
/// upstream changes to span emission. Sound today because Glue runs one
/// session per process; revisit when that stops being true.
TraceExportResult exportSessionTrace({
  required Environment env,
  required String sessionId,
  String? outputPath,
}) {
  final meta = _loadSessionMeta(env, sessionId);
  final windowStart = meta.startTime.toUtc();
  final windowEnd = (meta.endTime ?? DateTime.now()).toUtc();

  final logFiles = _spanLogsInWindow(env.logsDir, windowStart, windowEnd);
  final allSpans = logFiles
      .expand((f) => parseSpansJsonl(File(f).readAsStringSync()))
      .toList();

  final inWindow = allSpans
      .where((s) => _withinWindow(s, windowStart, windowEnd))
      .toList();
  final droppedInFlight = inWindow.where((s) => s['end_time'] == null).length;

  final json = spansToChromeTrace(
    inWindow,
    sessionId: sessionId,
    version: AppConstants.version,
  );

  final dest = outputPath ?? p.join(env.sessionDir(meta.id), 'trace.json');
  final destFile = File(dest);
  destFile.parent.createSync(recursive: true);
  destFile.writeAsStringSync(json);

  return TraceExportResult(
    sessionId: sessionId,
    outputPath: dest,
    spanCount: inWindow.length - droppedInFlight,
    droppedInFlight: droppedInFlight,
    scannedLogFiles: logFiles,
  );
}

/// Newest session by `start_time`. `null` when `sessionsDir` is empty.
SessionMeta? findLatestSession(Environment env) {
  final dir = Directory(env.sessionsDir);
  if (!dir.existsSync()) return null;
  final metas = SessionStore.listSessions(env.sessionsDir);
  return metas.isEmpty ? null : metas.first;
}

SessionMeta _loadSessionMeta(Environment env, String sessionId) {
  final metaFile = File(p.join(env.sessionsDir, sessionId, 'meta.json'));
  if (!metaFile.existsSync()) {
    throw TraceExportException(
      'Session not found: $sessionId (no meta.json at ${metaFile.path})',
    );
  }
  return SessionStore.listSessions(env.sessionsDir).firstWhere(
    (m) => m.id.value == sessionId,
    orElse: () =>
        throw TraceExportException('Failed to parse meta.json for $sessionId'),
  );
}

/// Returns the absolute paths of `spans-YYYY-MM-DD.jsonl` files whose date
/// (parsed from the filename) lies within the inclusive [start]..[end] window
/// in UTC. Sorted ascending so the output file lists files in the order they
/// were written.
List<String> _spanLogsInWindow(String logsDir, DateTime start, DateTime end) {
  final dir = Directory(logsDir);
  if (!dir.existsSync()) return const [];
  final startDate = DateTime.utc(start.year, start.month, start.day);
  final endDate = DateTime.utc(end.year, end.month, end.day);
  return dir.listSync().whereType<File>().map((f) => f.path).where((path) {
    final name = p.basename(path);
    if (!name.startsWith('spans-') || !name.endsWith('.jsonl')) {
      return false;
    }
    final dateStr = name.substring(
      'spans-'.length,
      name.length - '.jsonl'.length,
    );
    final date = DateTime.tryParse('${dateStr}T00:00:00Z');
    if (date == null) return false;
    return !date.isBefore(startDate) && !date.isAfter(endDate);
  }).toList()..sort();
}

bool _withinWindow(
  Map<String, dynamic> span,
  DateTime windowStart,
  DateTime windowEnd,
) {
  final startRaw = span['start_time'];
  if (startRaw is! String) return false;
  final start = DateTime.tryParse(startRaw)?.toUtc();
  if (start == null) return false;
  return !start.isBefore(windowStart) && !start.isAfter(windowEnd);
}

/// `glue trace …` — convert recorded observability spans into a
/// [Firefox Profiler](https://profiler.firefox.com)–compatible trace file
/// (Chrome Trace Event Format). The conversion reads `$GLUE_HOME/logs/
/// spans-*.jsonl` produced by `FileSink` and filters to one session via
/// its `meta.json` time range.
class TraceCommand extends Command<int> {
  TraceCommand() {
    addSubcommand(TraceExportCommand());
  }

  @override
  String get name => 'trace';

  @override
  String get description =>
      'Export recorded spans as a Firefox Profiler trace (Chrome Trace Event Format).';
}

class TraceExportCommand extends Command<int> {
  TraceExportCommand() {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        help:
            'Destination path. Defaults to '
            '<sessions>/<sessionId>/trace.json.',
      )
      ..addFlag(
        'latest',
        negatable: false,
        help:
            'Export the most recent session instead of requiring a session id.',
      )
      ..addFlag(
        'open',
        negatable: false,
        help:
            'Also open https://profiler.firefox.com in the default browser '
            '(drag the written file into the page to load it).',
      );
  }

  @override
  String get name => 'export';

  @override
  String get description =>
      'Write a session\'s spans as a Chrome Trace Event JSON file.';

  @override
  String get invocation => 'glue trace export [<sessionId>] [options]';

  @override
  Future<int> run() async {
    final env = Environment.detect();
    final rest = argResults!.rest;
    final useLatest = argResults!.flag('latest');

    String sessionId;
    if (useLatest) {
      final latest = findLatestSession(env);
      if (latest == null) {
        stderr.writeln('No sessions found in ${env.sessionsDir}.');
        return 1;
      }
      sessionId = latest.id.value;
    } else if (rest.isEmpty) {
      stderr.writeln(
        'Usage: glue trace export <sessionId> [--output <path>] [--open]\n'
        '       glue trace export --latest [--output <path>] [--open]',
      );
      return 64;
    } else {
      sessionId = rest.first;
    }

    final TraceExportResult result;
    try {
      result = exportSessionTrace(
        env: env,
        sessionId: sessionId,
        outputPath: argResults!.option('output'),
      );
    } on TraceExportException catch (e) {
      stderr.writeln(e.message);
      return 1;
    }

    stdout.writeln(formatTraceExportResult(result));

    if (argResults!.flag('open')) {
      await openInBrowser('https://profiler.firefox.com');
    }
    return 0;
  }
}
