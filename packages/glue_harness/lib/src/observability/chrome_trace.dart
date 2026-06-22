import 'dart:convert';

/// Converts a stream of serialized span maps — the JSONL shape produced by
/// `ObservabilitySpan.toMap` (and written by `FileSink`) — into a JSON string
/// in [Chrome Trace Event Format](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU/preview),
/// which [Firefox Profiler](https://profiler.firefox.com) imports natively
/// via `src/profile-logic/import/chrome.ts`.
///
/// Mapping rules:
///
/// * Each completed span -> one `X` (Complete) event with `ts` and `dur` in
///   microseconds since epoch. Spans missing `end_time` are dropped (they
///   were in-flight when the log was sampled and have no duration).
/// * Spans sharing a `trace_id` share a `tid`. Firefox Profiler renders
///   overlapping intervals on the same tid as visually nested, which matches
///   parent/child span semantics. Each new `trace_id` gets the next integer
///   tid in first-seen order.
/// * Per-span `events[]` entries -> `i` (Instant) events on the same tid,
///   scoped to the thread (`s: "t"`).
/// * Span `kind` -> Chrome `cat`. Categories drive marker colors in the UI.
/// * `M` metadata events name the process and each thread (after the trace's
///   root span — the one with no `parent_span_id` within the trace, falling
///   back to the earliest-started span).
/// * Spans with `status_code == "error"` get `args.data.glue.status = "error"`
///   so the UI tooltip surfaces failures without polluting marker names.
///
/// The output uses the envelope form
/// `{"traceEvents": [...], "displayTimeUnit": "ms", "otherData": {...}}`
/// rather than a bare array, so [sessionId] and [version] show up in the
/// profiler's "Profile Info" panel.
String spansToChromeTrace(
  Iterable<Map<String, dynamic>> spans, {
  required String sessionId,
  String processName = 'glue',
  String? version,
}) {
  final completedSpans = spans
      .where((s) => s['end_time'] != null && s['start_time'] != null)
      .toList();

  // Assign tid per trace_id in first-seen order, and pick a name for each
  // thread (root span = parent-less span, else earliest-started).
  final tidByTrace = <String, int>{};
  final rootByTid = <int, Map<String, dynamic>>{};
  for (final s in completedSpans) {
    final traceId = s['trace_id'] as String;
    final tid = tidByTrace.putIfAbsent(traceId, () => tidByTrace.length);
    final existingRoot = rootByTid[tid];
    if (existingRoot == null) {
      rootByTid[tid] = s;
      continue;
    }
    final existingHasParent = existingRoot['parent_span_id'] != null;
    final candidateHasParent = s['parent_span_id'] != null;
    if (existingHasParent && !candidateHasParent) {
      rootByTid[tid] = s;
      continue;
    }
    if (existingHasParent == candidateHasParent) {
      final existingStart = DateTime.parse(
        existingRoot['start_time'] as String,
      );
      final candidateStart = DateTime.parse(s['start_time'] as String);
      if (candidateStart.isBefore(existingStart)) rootByTid[tid] = s;
    }
  }

  final traceEvents = <Map<String, dynamic>>[
    {
      'name': 'process_name',
      'ph': 'M',
      'pid': 1,
      'tid': 0,
      'args': {'name': processName},
    },
    ...rootByTid.entries.map(
      (e) => {
        'name': 'thread_name',
        'ph': 'M',
        'pid': 1,
        'tid': e.key,
        'args': {'name': e.value['name'] as String},
      },
    ),
    ...completedSpans.expand(
      (s) => _spanToEvents(s, tidByTrace[s['trace_id'] as String]!),
    ),
  ];

  return jsonEncode({
    'traceEvents': traceEvents,
    'displayTimeUnit': 'ms',
    'otherData': {'glue.sessionId': sessionId, 'glue.version': ?version},
  });
}

Iterable<Map<String, dynamic>> _spanToEvents(
  Map<String, dynamic> span,
  int tid,
) sync* {
  final start = DateTime.parse(span['start_time'] as String);
  final end = DateTime.parse(span['end_time'] as String);
  final attrs = Map<String, dynamic>.from(
    (span['attributes'] as Map?) ?? const {},
  );
  if (span['status_code'] == 'error') {
    attrs['glue.status'] = 'error';
    if (span['status_message'] != null) {
      attrs['glue.status_message'] = span['status_message'];
    }
  }

  yield {
    'name': span['name'],
    'cat': span['kind'],
    'ph': 'X',
    'pid': 1,
    'tid': tid,
    'ts': start.microsecondsSinceEpoch,
    'dur': end.difference(start).inMicroseconds,
    'args': {'data': attrs},
  };

  for (final event in (span['events'] as List? ?? const [])) {
    final e = event as Map<String, dynamic>;
    yield {
      'name': e['name'],
      'cat': span['kind'],
      'ph': 'i',
      's': 't',
      'pid': 1,
      'tid': tid,
      'ts': DateTime.parse(e['timestamp'] as String).microsecondsSinceEpoch,
      'args': {'data': e['attributes'] ?? const {}},
    };
  }
}

/// Reads a list of newline-delimited JSON span records from [jsonl] — the
/// shape produced by `FileSink` and stored in `$GLUE_HOME/logs/spans-*.jsonl`.
/// Malformed or empty lines are silently skipped, matching how
/// `SessionStore.loadConversation` reads its sibling JSONL file.
List<Map<String, dynamic>> parseSpansJsonl(String jsonl) {
  final spans = <Map<String, dynamic>>[];
  for (final line in const LineSplitter().convert(jsonl)) {
    if (line.trim().isEmpty) continue;
    try {
      spans.add(jsonDecode(line) as Map<String, dynamic>);
    } catch (_) {
      // Tolerate corrupt lines — same policy as the conversation reader.
    }
  }
  return spans;
}
