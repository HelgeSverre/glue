import 'dart:io';

import 'package:glue/glue.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:glue/src/commands/slash/mcp.dart';
import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/conversation/entry.dart';
import 'package:glue/src/services/approval_state.dart';
import 'package:glue/src/services/conversation_view.dart';
import 'package:glue/src/services/lifecycle.dart';
import 'package:glue/src/ui/dock_manager.dart';
import 'package:test/test.dart';

class _NoopLlm implements LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {}
}

class _Fixture {
  _Fixture({McpClientPool? pool}) {
    final tmp = Directory.systemTemp.createTempSync('mcp_slash_test_');
    environment = Environment.test(home: tmp.path, cwd: tmp.path);
    session = SessionManager(environment: environment);
    skills = SkillRuntime(cwd: tmp.path, extraPathsProvider: () => const []);
    agent = AgentCore(llm: _NoopLlm(), tools: const {});
    blocks = <ConversationEntry>[];
    panelStack = <PanelOverlay>[];
    subagentGroups = <String, SubagentGroup>{};
    editor = TextAreaEditor();
    conversation = ConversationView(
      blocks: blocks,
      subagentGroups: subagentGroups,
      streamingTextGetter: () => '',
      render: () {},
      resetStreamingText: () {},
      clearScreen: () {},
      resetScrollOffset: () {},
      clearToolUi: () {},
      clearSubagentGroups: () => subagentGroups.clear(),
    );
    approval = ApprovalState(get: () => ApprovalMode.confirm, set: (_) {});
    lifecycle = Lifecycle(onExit: () {});
    panels = ModalSurface(panelStack: panelStack, render: () {});
    dockManager = DockManager();
    mcpPool = pool ??
        McpClientPool(
          config: const McpConfig(),
          credentials: CredentialStore(
            path: '${environment.glueDir}/credentials.json',
            env: const {},
          ),
        );
  }

  late final Environment environment;
  late final SessionManager session;
  late final SkillRuntime skills;
  late final AgentCore agent;
  late final List<ConversationEntry> blocks;
  late final List<PanelOverlay> panelStack;
  late final Map<String, SubagentGroup> subagentGroups;
  late final TextAreaEditor editor;
  late final ConversationView conversation;
  late final ApprovalState approval;
  late final Lifecycle lifecycle;
  late final ModalSurface panels;
  late final DockManager dockManager;
  late final McpClientPool mcpPool;

  SlashCommandContext get ctx => SlashCommandContext(
        configGetter: () => null,
        llmFactoryGetter: () => null,
        agentGetter: () => agent,
        cwdGetter: () => environment.cwd,
        modelIdGetter: () => 'test/model',
        isIdleGetter: () => true,
        environment: environment,
        session: session,
        skills: skills,
        debug: null,
        dockManager: dockManager,
        editor: editor,
        mcpPool: mcpPool,
        autoApprovedTools: const <String>{},
        ensureSession: () {},
        backfillTitle: (_) {},
        switchModel: (_) => '',
        conversation: conversation,
        approval: approval,
        lifecycle: lifecycle,
        panels: panels,
        commandsGetter: () => const <SlashCommand>[],
      );
}

void main() {
  group('McpSlashCommand', () {
    test('no servers configured → /mcp list prints friendly empty message', () {
      final fx = _Fixture();
      final cmd = McpSlashCommand(fx.ctx);
      final result = cmd.execute(['list']);
      expect(result, contains('No MCP servers configured'));
      expect(result, contains('mcp.servers'));
    });

    test('/mcp list emits text rows for each configured server', () {
      final tmp = Directory.systemTemp.createTempSync('mcp_slash_test_');
      final env = Environment.test(home: tmp.path, cwd: tmp.path);
      final pool = McpClientPool(
        config: const McpConfig(servers: [
          McpStdioServerSpec(id: 'fs', command: 'fake'),
          McpStdioServerSpec(id: 'db', command: 'fake', enabled: false),
        ]),
        credentials: CredentialStore(
          path: '${env.glueDir}/credentials.json',
          env: const {},
        ),
      );
      final fx = _Fixture(pool: pool);
      final cmd = McpSlashCommand(fx.ctx);

      final result = cmd.execute(['list']);
      expect(result, contains('MCP servers:'));
      expect(result, contains('fs'));
      expect(result, contains('db'));
      expect(result, contains('disconnected'));
    });

    test('/mcp with no args opens a panel (returns empty)', () {
      final tmp = Directory.systemTemp.createTempSync('mcp_slash_test_');
      final env = Environment.test(home: tmp.path, cwd: tmp.path);
      final pool = McpClientPool(
        config: const McpConfig(servers: [
          McpStdioServerSpec(id: 'fs', command: 'fake'),
        ]),
        credentials: CredentialStore(
          path: '${env.glueDir}/credentials.json',
          env: const {},
        ),
      );
      final fx = _Fixture(pool: pool);
      final cmd = McpSlashCommand(fx.ctx);

      final result = cmd.execute(const []);
      expect(result, isEmpty,
          reason: 'panel mode returns empty; the panel is pushed instead');
      expect(fx.panelStack, hasLength(1));
    });

    test('unknown subcommand → usage hint pointing at /mcp help', () {
      final fx = _Fixture();
      final cmd = McpSlashCommand(fx.ctx);
      final result = cmd.execute(['something']);
      expect(result, contains('Unknown'));
      expect(result, contains('/mcp help'));
    });

    test('/mcp help lists the subcommands', () {
      final fx = _Fixture();
      final cmd = McpSlashCommand(fx.ctx);
      final result = cmd.execute(['help']);
      expect(result, contains('/mcp list'));
      expect(result, contains('/mcp tools'));
      expect(result, contains('/mcp auth'));
    });
  });
}
