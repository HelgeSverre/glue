import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:glue/src/mcp/mcp_config.dart';

void main() {
  group('McpConfig', () {
    group('McpConfig.load from mcp.json', () {
      late Directory tempDir;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('mcp_config_test_');
      });

      tearDown(() {
        tempDir.deleteSync(recursive: true);
      });

      test('parses stdio server from global mcp.json', () {
        final json = jsonEncode({
          'mcpServers': {
            'filesystem': {
              'command': 'npx',
              'args': ['-y', '@modelcontextprotocol/server-filesystem'],
              'env': {'FOO': 'bar'},
              'autoConnect': true,
            },
          },
        });
        File('${tempDir.path}/mcp.json').writeAsStringSync(json);

        final config = McpConfig.load(glueDir: tempDir.path);
        expect(config.servers, contains('filesystem'));

        final server = config.servers['filesystem']!;
        expect(server.id, 'filesystem');
        expect(server.name, 'filesystem');
        expect(server.autoConnect, isTrue);
        expect(server.enabled, isTrue);
        expect(server.source, McpServerSource.global);

        final transport = server.transport as McpStdioConfig;
        expect(transport.command, 'npx');
        expect(
            transport.args, ['-y', '@modelcontextprotocol/server-filesystem']);
        expect(transport.env, {'FOO': 'bar'});
      });

      test('parses SSE server from global mcp.json', () {
        final json = jsonEncode({
          'mcpServers': {
            'remote': {
              'url': 'https://mcp.example.com/sse',
              'transport': 'sse',
            },
          },
        });
        File('${tempDir.path}/mcp.json').writeAsStringSync(json);

        final config = McpConfig.load(glueDir: tempDir.path);
        final server = config.servers['remote']!;
        final transport = server.transport as McpSseConfig;
        expect(transport.url, Uri.parse('https://mcp.example.com/sse'));
      });

      test('parses streamable-http server from global mcp.json', () {
        final json = jsonEncode({
          'mcpServers': {
            'db': {
              'url': 'https://mcp.example.com/db',
              'transport': 'streamable-http',
            },
          },
        });
        File('${tempDir.path}/mcp.json').writeAsStringSync(json);

        final config = McpConfig.load(glueDir: tempDir.path);
        final server = config.servers['db']!;
        final transport = server.transport as McpStreamableHttpConfig;
        expect(transport.url, Uri.parse('https://mcp.example.com/db'));
        expect(server.source, McpServerSource.global);
      });

      test('uses id as name when name is absent', () {
        final json = jsonEncode({
          'mcpServers': {
            'myserver': {'command': 'myserver'},
          },
        });
        File('${tempDir.path}/mcp.json').writeAsStringSync(json);

        final config = McpConfig.load(glueDir: tempDir.path);
        expect(config.servers['myserver']!.name, 'myserver');
      });

      test('skips entries without command or url', () {
        final json = jsonEncode({
          'mcpServers': {
            'bad': {'somethingElse': 'value'},
          },
        });
        File('${tempDir.path}/mcp.json').writeAsStringSync(json);

        final config = McpConfig.load(glueDir: tempDir.path);
        expect(config.servers, isEmpty);
      });

      test('ignores malformed mcp.json gracefully', () {
        File('${tempDir.path}/mcp.json').writeAsStringSync('not json {');

        final config = McpConfig.load(glueDir: tempDir.path);
        expect(config.servers, isEmpty);
      });

      test('sets autoConnect from auto_connect snake_case', () {
        final json = jsonEncode({
          'mcpServers': {
            's': {'command': 'cmd', 'auto_connect': true},
          },
        });
        File('${tempDir.path}/mcp.json').writeAsStringSync(json);

        final config = McpConfig.load(glueDir: tempDir.path);
        expect(config.servers['s']!.autoConnect, isTrue);
      });
    });

    group('McpConfig.load precedence', () {
      late Directory tempDir;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('mcp_prec_test_');
      });

      tearDown(() {
        tempDir.deleteSync(recursive: true);
      });

      test('loads from project-local .glue/mcp.json', () {
        final cwdDir = Directory('${tempDir.path}/project')..createSync();
        final glueDir = Directory('${cwdDir.path}/.glue')..createSync();
        final json = jsonEncode({
          'mcpServers': {
            'project-server': {'command': 'pserver'},
          },
        });
        File('${glueDir.path}/mcp.json').writeAsStringSync(json);

        final config = McpConfig.load(
          glueDir: '${tempDir.path}/nonexistent',
          cwd: cwdDir.path,
        );
        expect(config.servers, contains('project-server'));
        expect(
            config.servers['project-server']!.source, McpServerSource.project);
      });

      test('project-local overrides global on id collision', () {
        // Global
        File('${tempDir.path}/mcp.json').writeAsStringSync(jsonEncode({
          'mcpServers': {
            'server': {'command': 'global-cmd'},
          },
        }));

        // Project-local
        final cwdDir = Directory('${tempDir.path}/proj')..createSync();
        final glueDir2 = Directory('${cwdDir.path}/.glue')..createSync();
        File('${glueDir2.path}/mcp.json').writeAsStringSync(jsonEncode({
          'mcpServers': {
            'server': {'command': 'project-cmd'},
          },
        }));

        final config = McpConfig.load(
          glueDir: tempDir.path,
          cwd: cwdDir.path,
        );
        expect(config.servers, contains('server'));
        final transport = config.servers['server']!.transport as McpStdioConfig;
        expect(transport.command, 'project-cmd');
        expect(config.servers['server']!.source, McpServerSource.project);
      });

      test('loads from inline config.yaml section', () {
        final config = McpConfig.load(
          glueDir: '${tempDir.path}/nonexistent',
          inlineSection: {
            'servers': {
              'inline-server': {'command': 'inline-cmd'},
            },
          },
        );
        expect(config.servers, contains('inline-server'));
        expect(config.servers['inline-server']!.source, McpServerSource.config);
      });

      test('returns empty config when no files exist', () {
        final config = McpConfig.load(glueDir: '${tempDir.path}/nonexistent');
        expect(config.isEmpty, isTrue);
      });
    });

    group('McpServerConfig', () {
      test('transportLabel returns stdio for McpStdioConfig', () {
        const config = McpServerConfig(
          id: 's',
          name: 's',
          transport: McpStdioConfig(command: 'cmd'),
        );
        expect(config.transportLabel, 'stdio');
      });

      test('transportLabel returns sse for McpSseConfig', () {
        final config = McpServerConfig(
          id: 's',
          name: 's',
          transport: McpSseConfig(url: Uri.parse('https://x.com')),
        );
        expect(config.transportLabel, 'sse');
      });

      test('transportLabel returns http for McpStreamableHttpConfig', () {
        final config = McpServerConfig(
          id: 's',
          name: 's',
          transport: McpStreamableHttpConfig(url: Uri.parse('https://x.com')),
        );
        expect(config.transportLabel, 'http');
      });
    });
  });
}
