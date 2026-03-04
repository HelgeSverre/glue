import 'dart:convert';
import 'dart:io';

import 'package:glue/src/observability/file_sink.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('file_sink_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('writes JSONL to file on onSpan', () async {
    final sink = FileSink(logsDir: tempDir.path);
    final span = ObservabilitySpan(name: 'test-span', kind: 'internal');
    span.end();
    sink.onSpan(span);
    await sink.flush();

    final files = tempDir.listSync().whereType<File>().toList();
    expect(files, hasLength(1));

    final lines =
        files.first.readAsLinesSync().where((l) => l.isNotEmpty).toList();
    expect(lines, hasLength(1));

    final decoded = jsonDecode(lines.first) as Map<String, dynamic>;
    expect(decoded['name'], 'test-span');
    expect(decoded['trace_id'], span.traceId);
    expect(decoded['span_id'], span.spanId);

    await sink.close();
  });

  test('file is created with date-based name', () async {
    final sink = FileSink(logsDir: tempDir.path);
    final span = ObservabilitySpan(name: 'test', kind: 'internal');
    span.end();
    sink.onSpan(span);
    await sink.flush();

    final files = tempDir.listSync().whereType<File>().toList();
    expect(files, hasLength(1));

    final today = DateTime.now().toIso8601String().substring(0, 10);
    expect(files.first.path, contains('spans-$today.jsonl'));

    await sink.close();
  });

  test('multiple spans written as separate lines', () async {
    final sink = FileSink(logsDir: tempDir.path);

    final span1 = ObservabilitySpan(name: 'span-1', kind: 'internal');
    span1.end();
    sink.onSpan(span1);

    final span2 = ObservabilitySpan(name: 'span-2', kind: 'tool');
    span2.end();
    sink.onSpan(span2);

    await sink.flush();

    final files = tempDir.listSync().whereType<File>().toList();
    final lines =
        files.first.readAsLinesSync().where((l) => l.isNotEmpty).toList();
    expect(lines, hasLength(2));

    final decoded1 = jsonDecode(lines[0]) as Map<String, dynamic>;
    final decoded2 = jsonDecode(lines[1]) as Map<String, dynamic>;
    expect(decoded1['name'], 'span-1');
    expect(decoded2['name'], 'span-2');

    await sink.close();
  });

  test('creates directory if it does not exist', () async {
    final nestedDir = '${tempDir.path}/nested/logs';
    final sink = FileSink(logsDir: nestedDir);
    final span = ObservabilitySpan(name: 'test', kind: 'internal');
    span.end();
    sink.onSpan(span);
    await sink.flush();

    expect(Directory(nestedDir).existsSync(), isTrue);

    await sink.close();
  });

  test('close flushes and closes the sink', () async {
    final sink = FileSink(logsDir: tempDir.path);
    final span = ObservabilitySpan(name: 'test', kind: 'internal');
    span.end();
    sink.onSpan(span);

    await sink.close();

    final files = tempDir.listSync().whereType<File>().toList();
    final lines =
        files.first.readAsLinesSync().where((l) => l.isNotEmpty).toList();
    expect(lines, hasLength(1));
  });
}
