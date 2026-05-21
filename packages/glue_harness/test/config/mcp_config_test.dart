import 'package:glue_harness/glue_harness.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

McpConfig parse(String yamlText, {Map<String, String> env = const {}}) {
  final root = loadYaml(yamlText);
  final map = root is YamlMap ? Map<String, dynamic>.from(root) : null;
  return parseMcpConfig(map?['mcp'], env);
}

void main() {
  group('parseMcpConfig — empty / defaults', () {
    test('returns defaults when the section is missing', () {
      final cfg = parseMcpConfig(null, const {});
      expect(cfg.servers, isEmpty);
      expect(cfg.callTimeoutSeconds, 30);
      expect(cfg.reconnect.enabled, isTrue);
      expect(cfg.reconnect.maxAttempts, 10);
      expect(cfg.subprocessEnv, McpSubprocessEnvMode.allowlist);
      expect(cfg.toolPolicy.autoApprove, isEmpty);
      expect(cfg.toolPolicy.deny, isEmpty);
    });

    test('rejects a non-mapping section', () {
      expect(
        () => parseMcpConfig('whoops', const {}),
        throwsA(isA<ConfigError>()),
      );
    });
  });

  group('parseMcpConfig — stdio server', () {
    test('parses command + args + scrubbed env block', () {
      final cfg = parse('''
mcp:
  servers:
    filesystem:
      command: npx
      args:
        - -y
        - "@modelcontextprotocol/server-filesystem"
        - /tmp/work
      env:
        DEBUG: "false"
''');
      expect(cfg.servers, hasLength(1));
      final fs = cfg.servers.single as McpStdioServerSpec;
      expect(fs.id, 'filesystem');
      expect(fs.command, 'npx');
      expect(fs.args, [
        '-y',
        '@modelcontextprotocol/server-filesystem',
        '/tmp/work',
      ]);
      expect(fs.env, {'DEBUG': 'false'});
      expect(fs.enabled, isTrue);
    });

    test('disabled: false parks the server without removing it', () {
      final cfg = parse('''
mcp:
  servers:
    postgres:
      command: /usr/local/bin/mcp-postgres
      enabled: false
''');
      final pg = cfg.servers.single as McpStdioServerSpec;
      expect(pg.enabled, isFalse);
    });
  });

  group('parseMcpConfig — HTTP server', () {
    test('parses url + bearer literal auth', () {
      final cfg = parse('''
mcp:
  servers:
    wiki:
      url: "https://mcp.example.com/wiki"
      auth:
        kind: bearer
        token: "literal-token-abc"
''');
      final wiki = cfg.servers.single as McpHttpServerSpec;
      expect(wiki.url.toString(), 'https://mcp.example.com/wiki');
      final auth = wiki.auth as McpBearerAuth;
      expect(auth.token, 'literal-token-abc');
    });

    test('OAuth auth captures kind without a token', () {
      final cfg = parse('''
mcp:
  servers:
    notion:
      url: "https://mcp.notion.com"
      auth:
        kind: oauth
''');
      final notion = cfg.servers.single as McpHttpServerSpec;
      expect(notion.auth, isA<McpOAuthAuth>());
    });

    test('ws:// or wss:// becomes a WebSocket spec', () {
      final cfg = parse('''
mcp:
  servers:
    ws-server:
      url: "wss://mcp.example.com/socket"
''');
      expect(cfg.servers.single, isA<McpWebSocketServerSpec>());
    });
  });

  group('parseMcpConfig — env-var expansion', () {
    test('expands \${VAR} from env at parse time', () {
      final cfg = parse(
        '''
mcp:
  servers:
    wiki:
      url: "https://mcp.example.com/wiki"
      auth:
        kind: bearer
        token: "\${WIKI_MCP_TOKEN}"
''',
        env: {'WIKI_MCP_TOKEN': 'secret-from-env'},
      );
      final auth =
          (cfg.servers.single as McpHttpServerSpec).auth as McpBearerAuth;
      expect(auth.token, 'secret-from-env');
    });

    test('fails loudly when a referenced env var is missing', () {
      expect(
        () => parse('''
mcp:
  servers:
    wiki:
      url: "https://mcp.example.com/wiki"
      auth:
        kind: bearer
        token: "\${MISSING_VAR}"
'''),
        throwsA(
          isA<ConfigError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('wiki'),
              contains('MISSING_VAR'),
              contains('auth.token'),
            ),
          ),
        ),
      );
    });

    test('empty env var is treated as missing', () {
      expect(
        () => parse(
          '''
mcp:
  servers:
    s:
      command: "\${MY_CMD}"
''',
          env: {'MY_CMD': ''},
        ),
        throwsA(isA<ConfigError>()),
      );
    });
  });

  group('parseMcpConfig — tool_policy', () {
    test('captures auto_approve and deny lists', () {
      final cfg = parse('''
mcp:
  tool_policy:
    auto_approve:
      - filesystem__read_file
      - filesystem__list_directory
    deny:
      - "*__delete_file"
''');
      expect(cfg.toolPolicy.autoApprove, [
        'filesystem__read_file',
        'filesystem__list_directory',
      ]);
      expect(cfg.toolPolicy.deny, ['*__delete_file']);
    });

    test('glob matching: exact, *__suffix, prefix__*', () {
      const policy = McpToolPolicy(
        autoApprove: ['filesystem__read_file', '*__search'],
        deny: ['*__delete_file'],
      );
      expect(policy.isAutoApproved('filesystem__read_file'), isTrue);
      expect(policy.isAutoApproved('github__search'), isTrue);
      expect(policy.isAutoApproved('github__delete_file'), isFalse);
      expect(policy.isDenied('filesystem__delete_file'), isTrue);
      expect(policy.isDenied('github__delete_file'), isTrue);
      expect(policy.isDenied('filesystem__read_file'), isFalse);
    });
  });

  group('parseMcpConfig — reconnect policy', () {
    test('applies defaults when section is missing', () {
      final cfg = parse('mcp: {}');
      expect(cfg.reconnect.enabled, isTrue);
      expect(cfg.reconnect.initialDelayMs, 500);
      expect(cfg.reconnect.maxDelayMs, 30000);
      expect(cfg.reconnect.maxAttempts, 10);
    });

    test('parses overrides', () {
      final cfg = parse('''
mcp:
  reconnect:
    enabled: false
    initial_delay_ms: 1000
    max_delay_ms: 60000
    max_attempts: 5
''');
      expect(cfg.reconnect.enabled, isFalse);
      expect(cfg.reconnect.initialDelayMs, 1000);
      expect(cfg.reconnect.maxDelayMs, 60000);
      expect(cfg.reconnect.maxAttempts, 5);
    });
  });

  group('parseMcpConfig — top-level options', () {
    test('call_timeout_seconds defaults to 30 and overrides', () {
      final cfg1 = parse('mcp: {}');
      expect(cfg1.callTimeoutSeconds, 30);
      final cfg2 = parse('''
mcp:
  call_timeout_seconds: 120
''');
      expect(cfg2.callTimeoutSeconds, 120);
    });

    test('subprocess_env: full opts out of env scrubbing', () {
      final cfg = parse('''
mcp:
  subprocess_env: full
''');
      expect(cfg.subprocessEnv, McpSubprocessEnvMode.full);
    });

    test('subprocess_env: invalid value fails loudly', () {
      expect(
        () => parse('''
mcp:
  subprocess_env: someInvalidMode
'''),
        throwsA(isA<ConfigError>()),
      );
    });
  });

  group('parseMcpConfig — error shapes', () {
    test('server with both command and url is rejected', () {
      expect(
        () => parse('''
mcp:
  servers:
    weird:
      command: foo
      url: "https://bar.com"
'''),
        throwsA(
          isA<ConfigError>().having(
            (e) => e.message,
            'message',
            allOf(contains('weird'), contains('command'), contains('url')),
          ),
        ),
      );
    });

    test('server with neither command nor url is rejected', () {
      expect(
        () => parse('''
mcp:
  servers:
    empty:
      enabled: true
'''),
        throwsA(isA<ConfigError>()),
      );
    });

    test('unknown auth kind is rejected with all valid options listed', () {
      expect(
        () => parse('''
mcp:
  servers:
    s:
      url: "https://example.com"
      auth:
        kind: super-secret
'''),
        throwsA(
          isA<ConfigError>().having(
            (e) => e.message,
            'message',
            allOf(contains('bearer'), contains('oauth'), contains('none')),
          ),
        ),
      );
    });
  });
}
