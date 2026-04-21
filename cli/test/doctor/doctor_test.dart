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
      File(env.configYamlPath)
          .writeAsStringSync('active_model: ollama/qwen2.5-coder:32b\n');

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
        report.findings.any((finding) =>
            finding.severity == DoctorSeverity.error &&
            finding.message.contains('config.yaml parse failed')),
        isTrue,
      );
    });

    test('reports missing active provider credentials', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);
      Directory(env.glueDir).createSync(recursive: true);
      File(env.configYamlPath)
          .writeAsStringSync('active_model: anthropic/claude-sonnet-4.6\n');

      final report = runDoctor(env);

      expect(report.hasErrors, isTrue);
      expect(
        report.findings.any((finding) =>
            finding.section == 'Config validation' &&
            finding.message.contains('Not connected to "anthropic"')),
        isTrue,
      );
    });

    test('reports malformed session files', () {
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

      final report = runDoctor(env);

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
  });
}
