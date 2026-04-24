import 'dart:io';

import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/web/browser/browser_config.dart';
import 'package:test/test.dart';

Directory _scratch() =>
    Directory.systemTemp.createTempSync('glue_config_test_');

Environment _envWith({
  required Directory home,
  Map<String, String> vars = const {},
}) {
  return Environment.test(home: home.path, vars: vars);
}

void main() {
  group('GlueConfig.load', () {
    test('uses catalog default when no CLI or env model is set', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final config = GlueConfig.load(
        environment: _envWith(home: home),
      );
      expect(config.activeModel.providerId, 'anthropic');
      expect(config.activeModel.modelId, 'claude-sonnet-4-6');
    });

    test('--model CLI arg takes priority', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final config = GlueConfig.load(
        cliModel: 'openai/gpt-5.4',
        environment: _envWith(home: home),
      );
      expect(config.activeModel, ModelRef.parse('openai/gpt-5.4'));
    });

    test('GLUE_MODEL env var wins over config but loses to CLI', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final fromEnv = GlueConfig.load(
        environment: _envWith(
          home: home,
          vars: {'GLUE_MODEL': 'openai/gpt-5.4'},
        ),
      );
      expect(fromEnv.activeModel, ModelRef.parse('openai/gpt-5.4'));

      final cliWins = GlueConfig.load(
        cliModel: 'anthropic/claude-haiku-4-5',
        environment: _envWith(
          home: home,
          vars: {'GLUE_MODEL': 'openai/gpt-5.4'},
        ),
      );
      expect(cliWins.activeModel.modelId, 'claude-haiku-4-5');
    });

    test('legacy v1 config format is rejected with a migration hint', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      Directory('${home.path}/.glue').createSync();
      File('${home.path}/.glue/config.yaml').writeAsStringSync('''
provider: anthropic
model: claude-sonnet-4-6
anthropic:
  api_key: sk-legacy
''');

      expect(
        () => GlueConfig.load(environment: _envWith(home: home)),
        throwsA(
          isA<ConfigError>().having(
            (e) => e.message,
            'message',
            contains('old (v1) format'),
          ),
        ),
      );
    });

    test('bare substring input no longer silently coerces', () {
      // The old resolver fuzzy-matched "sonnet" → the first catalog entry
      // containing it. That masked typos and hid which provider was picked.
      // The new policy: exact match or error. "sonnet" is neither an id nor
      // a display name, so it should raise.
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      expect(
        () => GlueConfig.load(
          cliModel: 'sonnet',
          environment: _envWith(home: home),
        ),
        throwsA(isA<ConfigError>()),
      );
    });

    test('loads Anchor browser backend from environment', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final config = GlueConfig.load(
        environment: _envWith(
          home: home,
          vars: {
            'GLUE_BROWSER_BACKEND': 'anchor',
            'ANCHOR_API_KEY': 'anchor-key',
          },
        ),
      );

      expect(config.webConfig.browser.backend, BrowserBackend.anchor);
      expect(config.webConfig.browser.anchorApiKey, 'anchor-key');
      expect(config.webConfig.browser.isConfigured, isTrue);
    });

    test('loads Hyperbrowser browser backend from environment', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final config = GlueConfig.load(
        environment: _envWith(
          home: home,
          vars: {
            'GLUE_BROWSER_BACKEND': 'hyperbrowser',
            'HYPERBROWSER_API_KEY': 'hb-key',
          },
        ),
      );

      expect(config.webConfig.browser.backend, BrowserBackend.hyperbrowser);
      expect(config.webConfig.browser.hyperbrowserApiKey, 'hb-key');
      expect(config.webConfig.browser.isConfigured, isTrue);
    });

    test('loads OTEL config from Phoenix environment aliases', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final config = GlueConfig.load(
        environment: _envWith(
          home: home,
          vars: {
            'PHOENIX_COLLECTOR_ENDPOINT':
                'https://app.phoenix.arize.com/s/helge-sverre',
            'PHOENIX_API_KEY': 'test-phoenix-key',
            'PHOENIX_PROJECT_NAME': 'phoenix-project',
          },
        ),
      );

      final otel = config.observability.otel;
      expect(otel.isConfigured, isTrue);
      expect(
        otel.endpoint,
        'https://app.phoenix.arize.com/s/helge-sverre',
      );
      expect(otel.headers['Authorization'], 'Bearer test-phoenix-key');
      expect(
        otel.resourceAttributes['openinference.project.name'],
        'phoenix-project',
      );
    });

    test('YAML OTEL config wins over standard environment fallback', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      Directory('${home.path}/.glue').createSync();
      File('${home.path}/.glue/config.yaml').writeAsStringSync('''
observability:
  otel:
    enabled: true
    endpoint: https://yaml.example.test
    headers:
      Authorization: Bearer yaml
    service_name: glue-yaml
    resource_attributes:
      openinference.project.name: yaml-project
''');
      final config = GlueConfig.load(
        environment: _envWith(
          home: home,
          vars: {
            'OTEL_EXPORTER_OTLP_TRACES_ENDPOINT': 'https://env.example.test',
            'OTEL_EXPORTER_OTLP_TRACES_HEADERS': 'Authorization=Bearer%20env',
            'OTEL_SERVICE_NAME': 'glue-env',
            'OTEL_RESOURCE_ATTRIBUTES':
                'openinference.project.name=env-project',
          },
        ),
      );

      final otel = config.observability.otel;
      expect(otel.endpoint, 'https://yaml.example.test');
      expect(otel.headers['Authorization'], 'Bearer yaml');
      expect(otel.serviceName, 'glue-yaml');
      expect(
        otel.resourceAttributes['openinference.project.name'],
        'yaml-project',
      );
    });

    test('standard OTEL environment variables are parsed and decoded', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final config = GlueConfig.load(
        environment: _envWith(
          home: home,
          vars: {
            'OTEL_EXPORTER_OTLP_ENDPOINT': 'https://collector.example.test',
            'OTEL_EXPORTER_OTLP_HEADERS':
                'Authorization=Bearer%20env,X-Trace-Tag=hello%2Cworld',
            'OTEL_SERVICE_NAME': 'glue-env',
            'OTEL_RESOURCE_ATTRIBUTES':
                'deployment.environment=dev,openinference.project.name=env-project',
          },
        ),
      );

      final otel = config.observability.otel;
      expect(otel.isConfigured, isTrue);
      expect(otel.endpoint, 'https://collector.example.test');
      expect(otel.headers['Authorization'], 'Bearer env');
      expect(otel.headers['X-Trace-Tag'], 'hello,world');
      expect(otel.serviceName, 'glue-env');
      expect(otel.resourceAttributes['deployment.environment'], 'dev');
      expect(
        otel.resourceAttributes['openinference.project.name'],
        'env-project',
      );
    });

    test('OTEL_SDK_DISABLED disables exporter auto-enable from environment',
        () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final config = GlueConfig.load(
        environment: _envWith(
          home: home,
          vars: {
            'OTEL_EXPORTER_OTLP_ENDPOINT': 'https://collector.example.test',
            'OTEL_SDK_DISABLED': 'true',
          },
        ),
      );

      expect(config.observability.otel.enabled, isFalse);
      expect(config.observability.otel.isConfigured, isFalse);
    });
  });

  group('GlueConfig.validate', () {
    test('succeeds for ollama (auth: none) with no credentials', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final config = GlueConfig.load(
        cliModel: 'ollama/qwen2.5-coder:32b',
        environment: _envWith(home: home),
      );
      expect(config.validate, returnsNormally);
    });

    test('throws for anthropic when ANTHROPIC_API_KEY is missing', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final config = GlueConfig.load(
        environment: _envWith(home: home),
      );
      expect(config.validate, throwsA(isA<ConfigError>()));
    });

    test('succeeds when ANTHROPIC_API_KEY is set', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final config = GlueConfig.load(
        environment: _envWith(
          home: home,
          vars: {'ANTHROPIC_API_KEY': 'sk-test'},
        ),
      );
      expect(config.validate, returnsNormally);
    });
  });

  group('GlueConfig.titleGenerationEnabled', () {
    test('defaults to true when nothing sets it', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final config = GlueConfig.load(environment: _envWith(home: home));
      expect(config.titleGenerationEnabled, isTrue);
    });

    test('YAML title_generation_enabled: false disables it', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      Directory('${home.path}/.glue').createSync();
      File('${home.path}/.glue/config.yaml').writeAsStringSync('''
active_model: anthropic/claude-sonnet-4.6
title_generation_enabled: false
''');
      final config = GlueConfig.load(environment: _envWith(home: home));
      expect(config.titleGenerationEnabled, isFalse);
    });

    test('env GLUE_TITLE_GENERATION_ENABLED=false overrides YAML=true', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      Directory('${home.path}/.glue').createSync();
      File('${home.path}/.glue/config.yaml').writeAsStringSync('''
active_model: anthropic/claude-sonnet-4.6
title_generation_enabled: true
''');
      final config = GlueConfig.load(
        environment: _envWith(
          home: home,
          vars: {'GLUE_TITLE_GENERATION_ENABLED': 'false'},
        ),
      );
      expect(config.titleGenerationEnabled, isFalse);
    });

    test('env GLUE_TITLE_GENERATION_ENABLED=true overrides YAML=false', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      Directory('${home.path}/.glue').createSync();
      File('${home.path}/.glue/config.yaml').writeAsStringSync('''
active_model: anthropic/claude-sonnet-4.6
title_generation_enabled: false
''');
      final config = GlueConfig.load(
        environment: _envWith(
          home: home,
          vars: {'GLUE_TITLE_GENERATION_ENABLED': 'true'},
        ),
      );
      expect(config.titleGenerationEnabled, isTrue);
    });
  });

  group('GlueConfig.resolveProvider / resolveModel', () {
    test('resolves known provider + model', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final config = GlueConfig.load(
        environment: _envWith(home: home),
      );
      final ref = ModelRef.parse('anthropic/claude-sonnet-4.6');
      final provider = config.resolveProvider(ref);
      final model = config.resolveModel(ref);
      expect(provider.id, 'anthropic');
      expect(model.id, 'claude-sonnet-4.6');
    });

    test('unknown provider throws ConfigError', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final config = GlueConfig.load(
        environment: _envWith(home: home),
      );
      expect(
        () => config.resolveProvider(ModelRef.parse('nowhere/xyz')),
        throwsA(isA<ConfigError>()),
      );
    });

    test('unknown model on known provider yields a synthetic ModelDef', () {
      final home = _scratch();
      addTearDown(() => home.deleteSync(recursive: true));
      final config = GlueConfig.load(
        environment: _envWith(home: home),
      );
      final model = config.resolveModel(
        ModelRef.parse('anthropic/my-custom-experiment'),
      );
      expect(model.id, 'my-custom-experiment');
    });
  });
}
