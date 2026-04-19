/// Tests CredentialStore against a temp directory so no real ~/.glue is
/// touched. File-permission assertions are POSIX-only (skipped on Windows).
library;

import 'dart:convert';
import 'dart:io';

import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/credentials/credential_ref.dart';
import 'package:glue/src/credentials/credential_store.dart';
import 'package:test/test.dart';

Directory _scratch() {
  return Directory.systemTemp.createTempSync('glue_credentials_test_');
}

void main() {
  group('CredentialStore.resolve', () {
    test('NoCredential resolves to null', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/credentials.json',
        env: const {},
      );
      expect(store.resolve(const NoCredential()), isNull);
    });

    test('InlineCredential returns its value', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/credentials.json',
        env: const {},
      );
      expect(store.resolve(const InlineCredential('sk-inline')), 'sk-inline');
    });

    test('EnvCredential reads from the injected environment', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/credentials.json',
        env: {'ANTHROPIC_API_KEY': 'sk-env'},
      );
      expect(store.resolve(const EnvCredential('ANTHROPIC_API_KEY')), 'sk-env');
      expect(store.resolve(const EnvCredential('MISSING')), isNull);
    });

    test('StoredCredential reads from ~/.glue/credentials.json', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/credentials.json').writeAsStringSync(
        jsonEncode({
          'version': 1,
          'providers': {
            'anthropic': {'api_key': 'sk-stored'},
          },
        }),
      );
      final store = CredentialStore(
        path: '${dir.path}/credentials.json',
        env: const {},
      );
      expect(
        store.resolve(const StoredCredential('anthropic')),
        'sk-stored',
      );
      expect(
        store.resolve(const StoredCredential('openai')),
        isNull,
      );
    });

    test('missing credentials file is treated as empty (not an error)', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/credentials.json',
        env: const {},
      );
      expect(store.resolve(const StoredCredential('anthropic')), isNull);
    });

    test('corrupt credentials file is self-healing via setApiKey', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/credentials.json';
      File(path).writeAsStringSync('{{ malformed json');

      final store = CredentialStore(path: path, env: const {});
      // Reads return empty rather than throwing.
      expect(store.resolve(const StoredCredential('anthropic')), isNull);
      // And setApiKey can still recover the file.
      store.setApiKey('anthropic', 'sk-recovered');
      expect(
        store.resolve(const StoredCredential('anthropic')),
        'sk-recovered',
      );
    });
  });

  group('CredentialStore.setApiKey / remove', () {
    test('setApiKey persists and round-trips', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/credentials.json',
        env: const {},
      );
      store.setApiKey('anthropic', 'sk-first');
      expect(store.resolve(const StoredCredential('anthropic')), 'sk-first');

      store.setApiKey('anthropic', 'sk-second');
      expect(store.resolve(const StoredCredential('anthropic')), 'sk-second');
    });

    test('setApiKey writes the credentials file with mode 0600', () {
      if (Platform.isWindows) return;
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/credentials.json';
      final store = CredentialStore(path: path, env: const {});
      store.setApiKey('anthropic', 'sk-first');

      final mode = File(path).statSync().mode & 0x1ff;
      expect(
        mode,
        0x180, // 0o600
        reason: 'credentials file must be owner-read/write only',
      );
    });

    test('remove clears a provider entry', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/credentials.json',
        env: const {},
      );
      store.setApiKey('anthropic', 'sk-gone');
      store.remove('anthropic');
      expect(store.resolve(const StoredCredential('anthropic')), isNull);
    });

    test('setApiKey cleans up .tmp files after a successful rename', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/credentials.json';
      final store = CredentialStore(path: path, env: const {});
      store.setApiKey('anthropic', 'sk-v1');
      store.setApiKey('openai', 'sk-v2');

      final decoded = jsonDecode(File(path).readAsStringSync()) as Map;
      final providers = decoded['providers'] as Map;
      expect((providers['anthropic'] as Map)['api_key'], 'sk-v1');
      expect((providers['openai'] as Map)['api_key'], 'sk-v2');
      expect(
        Directory(dir.path)
            .listSync()
            .where((e) => e.path.endsWith('.tmp'))
            .length,
        0,
        reason: 'temp files must be cleaned up after atomic rename',
      );
    });
  });

  group('CredentialStore.resolveForProvider', () {
    ProviderDef provider({
      required String id,
      required AuthSpec auth,
    }) =>
        ProviderDef(
          id: id,
          name: id,
          adapter: 'openai',
          auth: auth,
          models: const {},
        );

    test('AuthKind.none resolves to null without touching env or store', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/credentials.json',
        env: const {},
      );
      final p =
          provider(id: 'ollama', auth: const AuthSpec(kind: AuthKind.none));
      expect(store.resolveForProvider(p), isNull);
    });

    test('AuthKind.apiKey pulls from environment', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/credentials.json',
        env: {'ANTHROPIC_API_KEY': 'sk-env'},
      );
      final p = provider(
        id: 'anthropic',
        auth:
            const AuthSpec(kind: AuthKind.apiKey, envVar: 'ANTHROPIC_API_KEY'),
      );
      expect(store.resolveForProvider(p), 'sk-env');
    });

    test('AuthKind.apiKey falls back to credentials.json', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/credentials.json',
        env: const {},
      );
      store.setApiKey('anthropic', 'sk-stored-fallback');
      final p = provider(
        id: 'anthropic',
        auth:
            const AuthSpec(kind: AuthKind.apiKey, envVar: 'ANTHROPIC_API_KEY'),
      );
      expect(
        store.resolveForProvider(p),
        'sk-stored-fallback',
        reason: 'env missing → try stored key under the same provider id',
      );
    });
  });
}
