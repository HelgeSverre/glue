import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:glue/src/storage/config_store.dart';

void main() {
  late Directory tempDir;
  late String configPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('config_store_test_');
    configPath = p.join(tempDir.path, 'config.json');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('load returns empty map when file missing', () {
    final store = ConfigStore(configPath);
    expect(store.load(), isEmpty);
  });

  test('save and load round-trip', () {
    final store = ConfigStore(configPath);
    final config = {
      'default_provider': 'anthropic',
      'default_model': 'claude-sonnet-4-6',
      'trusted_tools': ['read_file', 'grep'],
      'debug': true,
    };
    store.save(config);

    final loaded = store.load();
    expect(loaded['default_provider'], 'anthropic');
    expect(loaded['default_model'], 'claude-sonnet-4-6');
    expect(loaded['trusted_tools'], ['read_file', 'grep']);
    expect(loaded['debug'], isTrue);
  });

  test('convenience getters work', () {
    final store = ConfigStore(configPath);
    store.save({
      'default_provider': 'openai',
      'default_model': 'gpt-4.1',
      'trusted_tools': ['bash'],
      'debug': false,
    });

    expect(store.defaultProvider, 'openai');
    expect(store.defaultModel, 'gpt-4.1');
    expect(store.trustedTools, ['bash']);
    expect(store.debug, isFalse);
  });

  test('convenience getters return defaults for missing keys', () {
    final store = ConfigStore(configPath);
    store.save({});

    expect(store.defaultProvider, isNull);
    expect(store.defaultModel, isNull);
    expect(store.trustedTools, isEmpty);
    expect(store.debug, isTrue);
  });

  test('save creates parent directories', () {
    final nestedPath = p.join(tempDir.path, 'a', 'b', 'config.json');
    final store = ConfigStore(nestedPath);
    store.save({'key': 'value'});

    expect(File(nestedPath).existsSync(), isTrue);
    final loaded = jsonDecode(File(nestedPath).readAsStringSync());
    expect(loaded['key'], 'value');
  });
}
