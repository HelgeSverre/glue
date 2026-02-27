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

  test('detects external file changes', () async {
    final store = ConfigStore(configPath);
    store.save({'default_model': 'gpt-4'});
    expect(store.defaultModel, 'gpt-4');

    // Simulate external edit — wait a moment for mtime to differ
    await Future.delayed(Duration(milliseconds: 50));
    const encoder = JsonEncoder.withIndent('  ');
    File(configPath).writeAsStringSync(
      encoder.convert({'default_model': 'claude-sonnet'}),
    );

    expect(store.defaultModel, 'claude-sonnet');
  });

  test('update() applies mutation and saves', () {
    final store = ConfigStore(configPath);
    store.save({'debug': true, 'trusted_tools': ['read_file']});

    store.update((c) {
      (c['trusted_tools'] as List).add('bash');
    });

    expect(store.trustedTools, ['read_file', 'bash']);
    // Verify persisted to disk
    final onDisk = jsonDecode(File(configPath).readAsStringSync());
    expect(onDisk['trusted_tools'], ['read_file', 'bash']);
  });

  test('handles corrupt JSON gracefully', () {
    final store = ConfigStore(configPath);
    store.save({'debug': false});
    expect(store.debug, isFalse);

    // Corrupt the file
    File(configPath).writeAsStringSync('not valid json{{{');

    // Should keep last-known-good cache
    expect(store.debug, isFalse);
  });
}
