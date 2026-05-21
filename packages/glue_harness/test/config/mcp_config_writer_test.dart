/// Tests for [McpConfigWriter] — covers the round-trip-safe mutations of
/// `mcp.servers.*` plus the comment-preservation guarantee that justifies
/// pulling in `package:yaml_edit`.
library;

import 'dart:io';

import 'package:glue_harness/glue_harness.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Directory _scratch() =>
    Directory.systemTemp.createTempSync('glue_mcp_writer_test_');

String _read(String path) => File(path).readAsStringSync();

/// Loads [path] as YAML and walks the typed map chain. Wraps the verbose
/// cast/index gymnastics that the strict-mode analyzer otherwise flags as
/// `avoid_dynamic_calls`.
Map<dynamic, dynamic> _serversMap(String path) {
  final yaml = loadYaml(_read(path)) as Map;
  final mcp = yaml['mcp'] as Map;
  return mcp['servers'] as Map;
}

Map<dynamic, dynamic> _serverEntry(String path, String id) =>
    _serversMap(path)[id] as Map;

void main() {
  group('McpConfigWriter.addServer', () {
    test(
      'adds stdio server to an empty config and the result re-parses',
      () async {
        final dir = _scratch();
        addTearDown(() => dir.deleteSync(recursive: true));
        final configPath = '${dir.path}/config.yaml';

        McpConfigWriter(configPath).addServer(
          const McpStdioServerSpec(
            id: 'playwright',
            command: 'npx',
            args: ['-y', '@playwright/mcp@latest'],
            env: {'PLAYWRIGHT_BROWSERS_PATH': '0'},
          ),
        );

        final servers = _serversMap(configPath);
        expect(servers.containsKey('playwright'), isTrue);
        final entry = _serverEntry(configPath, 'playwright');
        expect(entry['command'], 'npx');
        expect(entry['args'], ['-y', '@playwright/mcp@latest']);
        expect((entry['env'] as Map)['PLAYWRIGHT_BROWSERS_PATH'], '0');

        // The full parser must also accept the file.
        final yaml = loadYaml(_read(configPath)) as Map;
        final parsed = parseMcpConfig(yaml['mcp'], const {});
        expect(parsed.servers, hasLength(1));
        expect(parsed.servers.first, isA<McpStdioServerSpec>());
      },
    );

    test('preserves comments and key order in a heavily-commented file', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final configPath = '${dir.path}/config.yaml';

      // Hand-crafted realistic config — mimics what a user would have.
      const original = '''# Glue config.yaml
# Top-of-file comment must survive.

# Model Configuration
active_model: anthropic/claude-sonnet-4-6  # inline comment
small_model: anthropic/claude-haiku-4-5

# Debugging
debug: true

# MCP block — already present.
mcp:
  servers:
    existing:
      command: existing-cmd
''';
      File(configPath).writeAsStringSync(original);

      McpConfigWriter(configPath).addServer(
        McpHttpServerSpec(
          id: 'github',
          url: Uri.parse('https://example.com/mcp'),
          auth: const McpBearerAuth(),
        ),
      );

      final after = _read(configPath);
      // Every comment line from the original must still be present.
      for (final line in original.split('\n').where((l) => l.startsWith('#'))) {
        expect(after, contains(line), reason: 'comment line dropped: "$line"');
      }
      expect(after, contains('# inline comment'));
      // Top-level keys keep their order: active_model before small_model.
      final activeIdx = after.indexOf('active_model');
      final smallIdx = after.indexOf('small_model');
      final debugIdx = after.indexOf('debug:');
      expect(activeIdx, lessThan(smallIdx));
      expect(smallIdx, lessThan(debugIdx));
      // New entry exists alongside the old one.
      expect(after, contains('existing:'));
      expect(after, contains('github:'));
    });

    test('rejects duplicate id without --force; overwrites with it', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final configPath = '${dir.path}/config.yaml';
      final writer = McpConfigWriter(configPath);

      writer.addServer(const McpStdioServerSpec(id: 'x', command: 'a'));
      expect(
        () => writer.addServer(const McpStdioServerSpec(id: 'x', command: 'b')),
        throwsA(isA<McpConfigWriteError>()),
      );

      writer.addServer(
        const McpStdioServerSpec(id: 'x', command: 'b'),
        overwrite: true,
      );
      expect(_serverEntry(configPath, 'x')['command'], 'b');
    });

    test(
      'creates mcp: block from scratch when bootstrapping from template',
      () {
        final dir = _scratch();
        addTearDown(() => dir.deleteSync(recursive: true));
        final configPath = '${dir.path}/config.yaml';
        // File does not exist — _mutate should bootstrap from template.

        McpConfigWriter(configPath).addServer(
          const McpStdioServerSpec(id: 'foo', command: '/usr/bin/env'),
        );

        final content = _read(configPath);
        expect(
          content,
          contains('# Glue config.yaml'),
          reason: 'template header preserved',
        );
        expect(content, contains('foo:'));
        expect(content, contains('command: /usr/bin/env'));

        // And the parser accepts it.
        final root = loadYaml(content) as Map;
        final parsed = parseMcpConfig(root['mcp'], const {});
        expect(parsed.servers.single, isA<McpStdioServerSpec>());
        expect(
          (parsed.servers.single as McpStdioServerSpec).command,
          '/usr/bin/env',
        );
      },
    );

    test('writes HTTP server with bearer auth block', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final configPath = '${dir.path}/config.yaml';

      McpConfigWriter(configPath).addServer(
        McpHttpServerSpec(
          id: 'api',
          url: Uri.parse('https://api.example.com/mcp'),
          auth: const McpBearerAuth(),
        ),
      );

      final spec = _serverEntry(configPath, 'api');
      expect(spec['url'], 'https://api.example.com/mcp');
      final auth = spec['auth'] as Map;
      expect(auth['kind'], 'bearer');
      // No token literal — stored credentials are out-of-band.
      expect(auth.containsKey('token'), isFalse);
    });

    test('omits enabled when true, writes it when false', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final configPath = '${dir.path}/config.yaml';

      final writer = McpConfigWriter(configPath);
      writer.addServer(const McpStdioServerSpec(id: 'on', command: 'a'));
      writer.addServer(
        const McpStdioServerSpec(id: 'off', command: 'b', enabled: false),
      );

      expect(_serverEntry(configPath, 'on').containsKey('enabled'), isFalse);
      expect(_serverEntry(configPath, 'off')['enabled'], false);
    });
  });

  group('McpConfigWriter.removeServer', () {
    test('removes the entry and the result still parses', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final configPath = '${dir.path}/config.yaml';

      final writer = McpConfigWriter(configPath);
      writer.addServer(const McpStdioServerSpec(id: 'a', command: 'x'));
      writer.addServer(const McpStdioServerSpec(id: 'b', command: 'y'));

      writer.removeServer('a');

      final servers = _serversMap(configPath);
      expect(servers.containsKey('a'), isFalse);
      expect(servers.containsKey('b'), isTrue);
    });

    test('throws when id is unknown', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final configPath = '${dir.path}/config.yaml';
      // File exists, just no server with that id.
      File(configPath).writeAsStringSync('# empty\n');

      expect(
        () => McpConfigWriter(configPath).removeServer('missing'),
        throwsA(isA<McpConfigWriteError>()),
      );
    });
  });

  group('McpConfigWriter.setEnabled', () {
    test('disables an enabled server and re-enables it', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final configPath = '${dir.path}/config.yaml';

      final writer = McpConfigWriter(configPath);
      writer.addServer(const McpStdioServerSpec(id: 'svc', command: 'x'));

      writer.setEnabled('svc', false);
      expect(_serverEntry(configPath, 'svc')['enabled'], false);

      writer.setEnabled('svc', true);
      expect(_serverEntry(configPath, 'svc')['enabled'], true);
    });

    test('throws when id is unknown', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final configPath = '${dir.path}/config.yaml';
      File(configPath).writeAsStringSync('mcp:\n  servers: {}\n');

      expect(
        () => McpConfigWriter(configPath).setEnabled('ghost', true),
        throwsA(isA<McpConfigWriteError>()),
      );
    });
  });

  group('McpConfigWriter.updateAuth', () {
    test('updateAuth writes kind:oauth + cached discovery URLs', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final configPath = '${dir.path}/config.yaml';
      File(configPath).writeAsStringSync('''
mcp:
  servers:
    foo:
      url: "https://foo.example/mcp"
''');

      final writer = McpConfigWriter(configPath);
      writer.updateAuth(
        'foo',
        auth: const McpOAuthAuth(),
        resourceMetadataUrl: Uri.parse(
          'https://foo.example/.well-known/oauth-protected-resource',
        ),
        authorizationServer: Uri.parse('https://auth.foo.example'),
      );

      final content = _read(configPath);
      expect(content, contains('kind: oauth'));
      expect(content, contains('resource_metadata_url:'));
      expect(content, contains('authorization_server:'));
    });

    test('updateAuth removes auth key when given McpNoAuth', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final configPath = '${dir.path}/config.yaml';
      File(configPath).writeAsStringSync('''
mcp:
  servers:
    foo:
      url: "https://foo.example/mcp"
      auth:
        kind: oauth
''');

      McpConfigWriter(configPath).updateAuth('foo', auth: const McpNoAuth());

      final entry = _serverEntry(configPath, 'foo');
      expect(entry.containsKey('auth'), isFalse);
    });

    test('updateAuth throws when server id is unknown', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final configPath = '${dir.path}/config.yaml';
      File(configPath).writeAsStringSync('mcp:\n  servers: {}\n');

      expect(
        () => McpConfigWriter(
          configPath,
        ).updateAuth('ghost', auth: const McpOAuthAuth()),
        throwsA(isA<McpConfigWriteError>()),
      );
    });
  });

  group('McpConfigWriter.hasServer', () {
    test('returns true/false based on YAML state', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final configPath = '${dir.path}/config.yaml';

      final writer = McpConfigWriter(configPath);
      expect(writer.hasServer('foo'), isFalse);

      writer.addServer(const McpStdioServerSpec(id: 'foo', command: 'x'));
      expect(writer.hasServer('foo'), isTrue);
      expect(writer.hasServer('bar'), isFalse);

      writer.removeServer('foo');
      expect(writer.hasServer('foo'), isFalse);
    });
  });
}
