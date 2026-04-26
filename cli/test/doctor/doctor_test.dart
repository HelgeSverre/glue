import 'dart:io';

import 'package:test/test.dart';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/doctor/doctor.dart';
import 'package:glue/src/providers/provider_adapter.dart';
import 'package:glue/src/providers/resolved.dart';

Directory _scratch() =>
    Directory.systemTemp.createTempSync('glue_doctor_test_');

void main() {
  group('runDoctor', () {
    test('reports clean local-model config without errors', () async {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);
      Directory(env.glueDir).createSync(recursive: true);
      File(env.configYamlPath)
          .writeAsStringSync('active_model: ollama/qwen2.5-coder:32b\n');

      final report = await runDoctor(env);
      final rendered = renderDoctorReport(report);

      expect(report.hasErrors, isFalse);
      expect(rendered, contains('Glue Doctor'));
      expect(rendered, contains('config.yaml parsed'));
    });

    test('reports invalid config.yaml', () async {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);
      Directory(env.glueDir).createSync(recursive: true);
      File(env.configYamlPath).writeAsStringSync('active_model: [unterminated');

      final report = await runDoctor(env);

      expect(report.hasErrors, isTrue);
      expect(
        report.findings.any((finding) =>
            finding.severity == DoctorSeverity.error &&
            finding.message.contains('config.yaml parse failed')),
        isTrue,
      );
    });

    test('reports missing active provider credentials', () async {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);
      Directory(env.glueDir).createSync(recursive: true);
      File(env.configYamlPath)
          .writeAsStringSync('active_model: anthropic/claude-sonnet-4.6\n');

      final report = await runDoctor(env);

      expect(report.hasErrors, isTrue);
      expect(
        report.findings.any((finding) =>
            finding.section == 'Config validation' &&
            finding.message.contains('Not connected to "anthropic"')),
        isTrue,
      );
    });

    test('reports malformed session files', () async {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);
      Directory(env.glueDir).createSync(recursive: true);
      File(env.configYamlPath)
          .writeAsStringSync('active_model: ollama/qwen2.5-coder:32b\n');
      final sessionDir = Directory('${env.sessionsDir}/bad-session')
        ..createSync(recursive: true);
      File('${sessionDir.path}/meta.json').writeAsStringSync('{bad json');
      File('${sessionDir.path}/conversation.jsonl')
          .writeAsStringSync('{"timestamp":"now"}\n');

      final report = await runDoctor(env);

      expect(report.hasErrors, isTrue);
      expect(
        report.findings.any(
            (finding) => finding.message.contains('meta.json parse failed')),
        isTrue,
      );
      expect(
        report.findings.any((finding) =>
            finding.message.contains('conversation.jsonl line 1 missing type')),
        isTrue,
      );
    });

    test('reports configured OTEL export without leaking header values',
        () async {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);
      Directory(env.glueDir).createSync(recursive: true);
      File(env.configYamlPath).writeAsStringSync('''
active_model: ollama/qwen2.5-coder:32b
observability:
  otel:
    enabled: true
    endpoint: https://collector.example.test/base
    headers:
      Authorization: Bearer super-secret
      X-Project: demo
    service_name: glue-otel
''');

      final report = await runDoctor(env);

      expect(
        report.findings.any((finding) =>
            finding.section == 'Observability' &&
            finding.message ==
                'OTEL export: on (https://collector.example.test/base/v1/traces)'),
        isTrue,
      );
      expect(
        report.findings.any((finding) =>
            finding.section == 'Observability' &&
            finding.message == 'OTEL service: glue-otel'),
        isTrue,
      );
      expect(
        report.findings.any((finding) =>
            finding.section == 'Observability' &&
            finding.message == 'OTEL headers: Authorization, X-Project'),
        isTrue,
      );
      expect(
        report.findings
            .any((finding) => finding.message.contains('super-secret')),
        isFalse,
      );
    });

    test('verbose=false skips Provider connectivity probe', () async {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);
      Directory(env.glueDir).createSync(recursive: true);
      File(env.configYamlPath)
          .writeAsStringSync('active_model: ollama/qwen2.5-coder:32b\n');

      final report = await runDoctor(env);

      expect(
        report.findings.any((f) => f.section == 'Provider connectivity'),
        isFalse,
        reason: 'probe must be opt-in via --verbose',
      );
    });

    test('verbose=true probes configured providers and renders ok', () async {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);
      Directory(env.glueDir).createSync(recursive: true);
      File(env.configYamlPath)
          .writeAsStringSync('active_model: ollama/qwen2.5-coder:32b\n');

      final report = await runDoctor(
        env,
        verbose: true,
        adaptersBuilder: (_) => AdapterRegistry([
          _FakeProbeAdapter('ollama', ProviderHealth.ok),
        ]),
      );

      final ollamaRow = report.findings.firstWhere(
        (f) =>
            f.section == 'Provider connectivity' &&
            f.message.startsWith('Ollama:'),
        orElse: () => throw StateError('expected Ollama probe row'),
      );
      expect(ollamaRow.severity, DoctorSeverity.ok);
      expect(ollamaRow.message, 'Ollama: ok');
    });

    test('verbose=true renders unauthorized as a hard error', () async {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);
      Directory(env.glueDir).createSync(recursive: true);
      File(env.configYamlPath)
          .writeAsStringSync('active_model: ollama/qwen2.5-coder:32b\n');

      final report = await runDoctor(
        env,
        verbose: true,
        adaptersBuilder: (_) => AdapterRegistry([
          _FakeProbeAdapter('ollama', ProviderHealth.unauthorized),
        ]),
      );

      final row = report.findings.firstWhere(
        (f) =>
            f.section == 'Provider connectivity' &&
            f.message.startsWith('Ollama:'),
      );
      expect(row.severity, DoctorSeverity.error);
      expect(row.message, contains('credentials rejected'));
      expect(report.hasErrors, isTrue);
    });

    test('verbose=true renders unreachable as gray (info)', () async {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);
      Directory(env.glueDir).createSync(recursive: true);
      File(env.configYamlPath)
          .writeAsStringSync('active_model: ollama/qwen2.5-coder:32b\n');

      final report = await runDoctor(
        env,
        verbose: true,
        adaptersBuilder: (_) => AdapterRegistry([
          _FakeProbeAdapter('ollama', ProviderHealth.unreachable),
        ]),
      );

      final row = report.findings.firstWhere(
        (f) =>
            f.section == 'Provider connectivity' &&
            f.message.startsWith('Ollama:'),
      );
      expect(row.severity, DoctorSeverity.info);
      expect(row.message, contains('unreachable'));
    });

    test('verbose=true skips providers whose adapter reports not-connected',
        () async {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);
      Directory(env.glueDir).createSync(recursive: true);
      File(env.configYamlPath)
          .writeAsStringSync('active_model: ollama/qwen2.5-coder:32b\n');

      // Anthropic is wired with a fake that forces isConnected=false, so it
      // must NOT be probed even though we registered it.
      final report = await runDoctor(
        env,
        verbose: true,
        adaptersBuilder: (_) => AdapterRegistry([
          _FakeProbeAdapter('ollama', ProviderHealth.ok),
          _FakeProbeAdapter(
            'anthropic',
            ProviderHealth.ok,
            forceConnected: false,
          ),
        ]),
      );

      final connectivityRows = report.findings
          .where((f) => f.section == 'Provider connectivity')
          .toList();
      expect(
        connectivityRows.any((f) => f.message.startsWith('Anthropic:')),
        isFalse,
      );
    });

    test('reports configured OTEL export for MLflow-style ingestion', () async {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);
      Directory(env.glueDir).createSync(recursive: true);
      File(env.configYamlPath).writeAsStringSync('''
active_model: ollama/qwen2.5-coder:32b
observability:
  otel:
    enabled: true
    endpoint: http://localhost:5000
    headers:
      x-mlflow-experiment-id: "123"
''');

      final report = await runDoctor(env);

      expect(
        report.findings.any((finding) =>
            finding.section == 'Observability' &&
            finding.message ==
                'OTEL export: on (http://localhost:5000/v1/traces)'),
        isTrue,
      );
      expect(
        report.findings.any((finding) =>
            finding.section == 'Observability' &&
            finding.message == 'OTEL headers: x-mlflow-experiment-id'),
        isTrue,
      );
    });
  });
}

class _FakeProbeAdapter extends ProviderAdapter {
  _FakeProbeAdapter(this._adapterId, this._health, {this.forceConnected});
  final String _adapterId;
  final ProviderHealth _health;

  /// When non-null, overrides [isConnected] regardless of credential store
  /// state — lets tests exercise the filter without touching the env.
  final bool? forceConnected;

  @override
  String get adapterId => _adapterId;

  @override
  ProviderHealth validate(ResolvedProvider provider) => _health;

  @override
  Future<ProviderHealth> probe(
    ResolvedProvider provider, {
    Duration timeout = const Duration(seconds: 5),
  }) async =>
      _health;

  @override
  bool isConnected(provider, store) {
    return forceConnected ?? super.isConnected(provider, store);
  }

  @override
  LlmClient createClient({
    required ResolvedProvider provider,
    required ResolvedModel model,
    required String systemPrompt,
  }) =>
      _FakeClient();
}

class _FakeClient implements LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) {
    throw UnimplementedError();
  }
}
