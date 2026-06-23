import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:glue/src/acp/cli_acp_delegate.dart';
import 'package:glue/src/terminal/brand.dart';
import 'package:glue/src/terminal/tty_style.dart';
import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:glue_server/glue_server.dart';

/// `glue acp` — expose Glue's harness over an external protocol.
///
/// Today: ACP over stdio (`--stdio`, the default) and WebSocket (`--port`).
/// Planned: other ACP transports and MCP-facing integration work. See:
///   docs/plans/2026-02-27-acp-webui.md
///   docs/plans/2026-04-29-mcp-client.md
///
/// Wires `AcpServer` (in glue_server) to a `CliAcpDelegate` that owns
/// per-session [AgentCore] instances, runs prompts through the harness,
/// and routes `PermissionGate` "ask" decisions through ACP's
/// `session/request_permission`.
class AcpCommand extends Command<int> {
  AcpCommand() {
    argParser
      ..addFlag(
        'stdio',
        defaultsTo: true,
        help:
            'Speak ACP over stdin/stdout (line-delimited JSON-RPC). '
            'This is the default and is what editors expect.',
      )
      ..addOption(
        'port',
        abbr: 'p',
        help:
            'Run the ACP server over WebSocket on the given port '
            '(implies --no-stdio). 0 binds an ephemeral port.',
      )
      ..addOption(
        'host',
        defaultsTo: '127.0.0.1',
        help:
            'Bind address for --port mode. Defaults to loopback; '
            'pass 0.0.0.0 to expose on all interfaces (use with care).',
      )
      ..addOption(
        'ws-path',
        defaultsTo: '/acp',
        help:
            'HTTP path that accepts the WebSocket upgrade. Use `*` to '
            'accept any path.',
      )
      ..addOption(
        'token',
        help:
            'Require this bearer token on every WS connection (sent as '
            '`Authorization: Bearer …` header or `?token=…` query). '
            'Required when --host is non-loopback.',
      )
      ..addOption(
        'protocol',
        defaultsTo: 'acp',
        allowed: ['acp'],
        help:
            'Protocol to serve. ACP only for now; MCP-client support '
            'lives in glue_strategies — see '
            'docs/plans/2026-04-29-mcp-client.md.',
      )
      ..addFlag(
        'debug',
        abbr: 'd',
        negatable: false,
        help: 'Enable debug observability sinks for the agent loop.',
      );
  }

  @override
  String get name => 'acp';

  @override
  String get description =>
      'Serve Glue\'s harness as an ACP agent over stdio or WebSocket.';

  @override
  String get usageFooter =>
      '\n'
      'glue acp speaks ACP (Agent Client Protocol) — it is meant to be\n'
      'spawned by an editor or notebook client, not run interactively.\n'
      '\n'
      'Editor setup (Zed, VS Code, JetBrains, Neovim, Emacs, marimo):\n'
      '  https://getglue.dev/docs/advanced/acp-server';

  @override
  Future<int> run() async {
    final portRaw = argResults!.option('port');
    final debug = argResults!.flag('debug');

    // Build process-wide harness services once. Per-connection state
    // lives in CliAcpDelegate instances created below.
    final services = await ServiceLocator.create(debug: debug);

    if (portRaw != null) {
      return _runWebSocket(
        services,
        portRaw,
        argResults!.option('host')!,
        argResults!.option('ws-path')!,
        argResults!.option('token'),
      );
    }
    return _runStdio(services);
  }

  Future<int> _runStdio(AppServices services) async {
    final delegate = CliAcpDelegate(services: services);
    final transport = LineDelimitedTransport(input: stdin, output: stdout);
    final server = AcpServer(
      transport: transport,
      delegate: delegate,
      config: _config(),
    );
    try {
      await server.serve();
    } finally {
      await transport.close();
      await services.obs.close();
    }
    return 0;
  }

  Future<int> _runWebSocket(
    AppServices services,
    String portRaw,
    String host,
    String wsPath,
    String? token,
  ) async {
    final port = int.tryParse(portRaw);
    if (port == null || port < 0 || port > 65535) {
      stderr.writeln('Error: --port must be an integer in 0..65535');
      return 64;
    }
    final address = await _resolveBindAddress(host);
    if (address == null) {
      stderr.writeln('Error: could not resolve --host "$host"');
      return 64;
    }
    // Refuse to bind a non-loopback address without a token: this is
    // the safety guarantee the docs promise.
    final isLoopback = address.isLoopback;
    if (!isLoopback && (token == null || token.isEmpty)) {
      stderr.writeln(
        'Error: --host ${address.host} requires --token. Refusing to '
        'bind a non-loopback address without an auth token.',
      );
      return 64;
    }
    final httpHost = AcpHttpHost(
      delegateFactory: () => CliAcpDelegate(services: services),
      config: _config(),
      path: wsPath,
      bearerToken: (token != null && token.isNotEmpty) ? token : null,
    );
    final boundPort = await httpHost.start(address: address, port: port);
    final url =
        'ws://${address.host}:$boundPort'
        '${wsPath == '*' ? '' : wsPath}';
    // stderr is the human banner channel here because stdout is reserved
    // for the ACP/JSON-RPC stream. styledOrPlain still suppresses ANSI when
    // stderr is captured (no TTY) or NO_COLOR is set.
    stderr.writeln(
      '$brandDot ${styledOrPlain('glue acp', (s) => s.bold)} '
      '${styledOrPlain('ACP over WebSocket', (s) => s.gray)}',
    );
    stderr.writeln('  $markerOk ${styledOrPlain('url ', (s) => s.gray)} $url');
    if (httpHost.bearerToken != null) {
      stderr.writeln(
        '  $markerWarn ${styledOrPlain('auth', (s) => s.gray)} '
        '${styledOrPlain('bearer token required', (s) => s.yellow)}',
      );
    }
    stderr.writeln(
      '  $markerInfo ${styledOrPlain('docs', (s) => s.gray)} '
      'https://getglue.dev/docs/advanced/acp-server',
    );
    stderr.writeln(
      '  $markerInfo ${styledOrPlain('stop', (s) => s.gray)} Ctrl+C',
    );

    // Run until SIGINT.
    final exitSignal = Completer<void>();
    final sigintSub = ProcessSignal.sigint.watch().listen((_) {
      if (!exitSignal.isCompleted) exitSignal.complete();
    });
    try {
      await exitSignal.future;
    } finally {
      await sigintSub.cancel();
      await httpHost.stop();
      await services.obs.close();
    }
    return 0;
  }

  AcpServerConfig _config() => const AcpServerConfig(
    protocolVersion: 1,
    agentInfo: AgentInfo(
      name: 'glue',
      title: 'Glue',
      version: AppConstants.version,
    ),
    agentCapabilities: {
      'promptCapabilities': {
        'image': true,
        'audio': false,
        'embeddedContext': false,
      },
      'sessionCapabilities': {'close': {}},
    },
    authMethods: [
      AuthMethod(
        id: 'glue-terminal-setup',
        name: 'Run Glue setup',
        description:
            'Open a terminal setup flow for Glue configuration and provider credentials.',
        type: 'terminal',
        args: ['setup', '--check'],
      ),
    ],
  );
}

Future<InternetAddress?> _resolveBindAddress(String host) async {
  if (host == '0.0.0.0') return InternetAddress.anyIPv4;
  if (host == '::') return InternetAddress.anyIPv6;
  final asLiteral = InternetAddress.tryParse(host);
  if (asLiteral != null) return asLiteral;
  try {
    final lookups = await InternetAddress.lookup(host);
    return lookups.isEmpty ? null : lookups.first;
  } on SocketException {
    return null;
  }
}
