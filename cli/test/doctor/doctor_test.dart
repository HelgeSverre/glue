import 'dart:io';

import 'package:glue/glue.dart';
import 'package:test/test.dart';

Directory _scratch() =>
    Directory.systemTemp.createTempSync('glue_doctor_test_');

void main() {
  group('runDoctor', () {
    test('reports clean local-model config without errors', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);
      Directory(env.glueDir).createSync(recursive: true);
      File(
        env.configYamlPath,
      ).writeAsStringSync('active_model: ollama/qwen2.5-coder:32b\n');

      final report = runDoctor(env);
      final rendered = renderDoctorReport(report);

      expect(report.hasErrors, isFalse);
      expect(rendered, contains('Glue Doctor'));
      expect(rendered, contains('config.yaml parsed'));
    });

    test('reports invalid config.yaml', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);
      Directory(env.glueDir).createSync(recursive: true);
      File(env.configYamlPath).writeAsStringSync('active_model: [unterminated');

      final report = runDoctor(env);

      expect(report.hasErrors, isTrue);
      expect(
        report.findings.any(
          (finding) =>
              finding.severity == DoctorSeverity.error &&
              finding.message.contains('config.yaml parse failed'),
        ),
        isTrue,
      );
    });

    test('reports missing active provider credentials', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);
      Directory(env.glueDir).createSync(recursive: true);
      File(
        env.configYamlPath,
      ).writeAsStringSync('active_model: anthropic/claude-sonnet-4.6\n');

      final report = runDoctor(env);

      expect(report.hasErrors, isTrue);
      expect(
        report.findings.any(
          (finding) =>
              finding.section == 'Config validation' &&
              finding.message.contains('Not connected to "anthropic"'),
        ),
        isTrue,
      );
    });

    test('reports malformed session files', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);
      Directory(env.glueDir).createSync(recursive: true);
      File(
        env.configYamlPath,
      ).writeAsStringSync('active_model: ollama/qwen2.5-coder:32b\n');
      final sessionDir = Directory('${env.sessionsDir}/bad-session')
        ..createSync(recursive: true);
      File('${sessionDir.path}/meta.json').writeAsStringSync('{bad json');
      File(
        '${sessionDir.path}/conversation.jsonl',
      ).writeAsStringSync('{"timestamp":"now"}\n');

      final report = runDoctor(env);

      expect(report.hasErrors, isTrue);
      expect(
        report.findings.any(
          (finding) => finding.message.contains('meta.json parse failed'),
        ),
        isTrue,
      );
      expect(
        report.findings.any(
          (finding) => finding.message.contains(
            'conversation.jsonl line 1 missing type',
          ),
        ),
        isTrue,
      );
    });

    test('reports configured OTEL export without leaking header values', () {
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

      final report = runDoctor(env);

      expect(
        report.findings.any(
          (finding) =>
              finding.section == 'Observability' &&
              finding.message ==
                  'OTEL export: on (https://collector.example.test/base/v1/traces)',
        ),
        isTrue,
      );
      expect(
        report.findings.any(
          (finding) =>
              finding.section == 'Observability' &&
              finding.message == 'OTEL service: glue-otel',
        ),
        isTrue,
      );
      expect(
        report.findings.any(
          (finding) =>
              finding.section == 'Observability' &&
              finding.message == 'OTEL headers: Authorization, X-Project',
        ),
        isTrue,
      );
      expect(
        report.findings.any(
          (finding) => finding.message.contains('super-secret'),
        ),
        isFalse,
      );
    });

    test('Agent model — silent when active catalogued model has the '
        'tools capability', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);
      Directory(env.glueDir).createSync(recursive: true);
      // qwen3-coder:30b is the default local model and is catalogued
      // with the `tools` capability — no Agent model finding expected.
      File(
        env.configYamlPath,
      ).writeAsStringSync('active_model: ollama/qwen3-coder:30b\n');

      final report = runDoctor(env);

      expect(
        report.findings.any((f) => f.section == 'Agent model'),
        isFalse,
        reason: 'no finding when model supports tool calling',
      );
    });

    test('Agent model — info finding when active catalogued model lacks '
        'tools (chat-only fallback)', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);
      Directory(env.glueDir).createSync(recursive: true);
      // Write a local override catalog with a tool-less model so the
      // check has something to flag. (No catalogued tool-less Ollama
      // models ship in the bundled catalog today, so we fabricate one.)
      File(env.modelsYamlPath).writeAsStringSync('''
version: 1
updated_at: 2026-05-21
defaults:
  model: ollama/chatty:7b
providers:
  ollama:
    name: Ollama
    adapter: ollama
    auth:
      api_key: none
    models:
      chatty:7b:
        name: Chatty 7B
        capabilities: [chat, local]
''');
      File(
        env.configYamlPath,
      ).writeAsStringSync('active_model: ollama/chatty:7b\n');

      final report = runDoctor(env);

      final agentFinding = report.findings
          .where((f) => f.section == 'Agent model')
          .toList();
      expect(agentFinding, hasLength(1));
      expect(agentFinding.single.severity, DoctorSeverity.info);
      expect(agentFinding.single.message, contains('ollama/chatty:7b'));
      expect(agentFinding.single.message, contains('chat-only mode'));
      expect(report.hasErrors, isFalse);
    });
  });
}
