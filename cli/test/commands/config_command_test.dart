import 'dart:io';

import 'package:test/test.dart';

import 'package:glue/src/commands/config_command.dart';
import 'package:glue/src/config/config_template.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/core/environment.dart';

void main() {
  group('initUserConfig', () {
    test('creates config.yaml under Environment.configYamlPath', () {
      final tempDir = Directory.systemTemp.createTempSync('glue_config_init_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final env = Environment.test(home: tempDir.path);
      final result = initUserConfig(env);

      expect(result.status, ConfigInitStatus.created);
      expect(result.path, env.configYamlPath);
      expect(File(env.configYamlPath).existsSync(), isTrue);
      expect(File(env.configYamlPath).readAsStringSync(),
          contains('active_model:'));
    });

    test('respects GLUE_HOME override', () {
      final tempDir = Directory.systemTemp.createTempSync('glue_config_init_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final glueHome = '${tempDir.path}${Platform.pathSeparator}custom-glue';
      final env = Environment.test(
        home: tempDir.path,
        vars: {'GLUE_HOME': glueHome},
      );
      final result = initUserConfig(env);

      expect(result.status, ConfigInitStatus.created);
      expect(result.path, '$glueHome${Platform.pathSeparator}config.yaml');
      expect(File(result.path).existsSync(), isTrue);
    });

    test('refuses to overwrite without force', () {
      final tempDir = Directory.systemTemp.createTempSync('glue_config_init_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final env = Environment.test(home: tempDir.path);
      Directory(env.glueDir).createSync(recursive: true);
      File(env.configYamlPath)
          .writeAsStringSync('active_model: custom/model\n');

      final result = initUserConfig(env);

      expect(result.status, ConfigInitStatus.exists);
      expect(File(env.configYamlPath).readAsStringSync(),
          'active_model: custom/model\n');
    });

    test('overwrites existing file with force', () {
      final tempDir = Directory.systemTemp.createTempSync('glue_config_init_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final env = Environment.test(home: tempDir.path);
      Directory(env.glueDir).createSync(recursive: true);
      File(env.configYamlPath)
          .writeAsStringSync('active_model: custom/model\n');

      final result = initUserConfig(env, force: true);

      expect(result.status, ConfigInitStatus.overwritten);
      expect(File(env.configYamlPath).readAsStringSync(),
          contains('Glue config.yaml'));
      expect(File(env.configYamlPath).readAsStringSync(),
          isNot(contains('custom/model')));
    });

    test('template uses v2 keys and omits stale top-level fields', () {
      final template = buildConfigTemplate();

      expect(template, contains('active_model:'));
      expect(template, contains('small_model:'));
      expect(template, contains('title_generation_enabled:'));
      expect(template, contains('docker:'));
      expect(template, contains('browserless:'));
      expect(template, contains('hyperbrowser:'));
      expect(template, isNot(contains('\nprovider: anthropic')));
      expect(template, isNot(contains('\nmodel: anthropic')));
      expect(template, isNot(contains('title_model:')));
    });

    test('written template loads through GlueConfig.load', () {
      final tempDir = Directory.systemTemp.createTempSync('glue_config_init_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final env = Environment.test(home: tempDir.path);
      initUserConfig(env);

      final config = GlueConfig.load(environment: env);

      expect(config.activeModel.providerId, isNotEmpty);
      expect(config.activeModel.modelId, isNotEmpty);
    });

    test('userConfigPath returns resolved config.yaml path', () {
      final env = Environment.test(
        home: '/tmp/home',
        vars: {'GLUE_HOME': '/tmp/custom-glue'},
      );

      expect(userConfigPath(env), '/tmp/custom-glue/config.yaml');
    });

    test('validateUserConfig returns ok for configured local model', () {
      final tempDir = Directory.systemTemp.createTempSync('glue_config_init_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final env = Environment.test(home: tempDir.path);
      Directory(env.glueDir).createSync(recursive: true);
      File(env.configYamlPath)
          .writeAsStringSync('active_model: ollama/qwen2.5-coder:32b\n');

      final result = validateUserConfig(env);

      expect(result.ok, isTrue);
      expect(result.message, contains('Config OK'));
    });

    test('validateUserConfig reports missing provider credentials', () {
      final tempDir = Directory.systemTemp.createTempSync('glue_config_init_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final env = Environment.test(home: tempDir.path);
      Directory(env.glueDir).createSync(recursive: true);
      File(env.configYamlPath)
          .writeAsStringSync('active_model: anthropic/claude-sonnet-4.6\n');

      final result = validateUserConfig(env);

      expect(result.ok, isFalse);
      expect(result.message, contains('Not connected to "anthropic"'));
    });
  });
}
