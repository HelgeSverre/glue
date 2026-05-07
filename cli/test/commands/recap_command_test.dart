import 'package:glue_harness/glue_harness.dart';
import 'package:glue/src/commands/slash/recap.dart';
import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/conversation/entry.dart';
import 'package:glue/src/services/approval_state.dart';
import 'package:glue/src/services/conversation_view.dart';
import 'package:glue/src/services/lifecycle.dart';
import 'package:glue/src/ui/dock_manager.dart';
import 'package:glue/src/ui/panel_controller.dart';
import 'package:glue/src/ui/panel_modal.dart';
import 'package:test/test.dart';

class _NoopLlm implements LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {}
}

class _Fixture {
  _Fixture() {
    final env = Environment.test(home: '/tmp', cwd: '/tmp/project');
    environment = env;
    session = SessionManager(environment: env);
    skills = SkillRuntime(cwd: env.cwd, extraPathsProvider: () => const []);
    agent = AgentCore(llm: _NoopLlm(), tools: const {});
    blocks = <ConversationEntry>[];
    panelStack = <PanelOverlay>[];
    conversation = ConversationView(
      blocks: blocks,
      streamingTextGetter: () => '',
      render: () {},
      resetStreamingText: () {},
      clearScreen: () {},
      resetScrollOffset: () {},
    );
    approval = ApprovalState(
      get: () => ApprovalMode.confirm,
      set: (_) {},
    );
    lifecycle = Lifecycle(onExit: () {});
    panels = PanelController(panelStack: panelStack, render: () {});
    dockManager = DockManager();
  }

  late final Environment environment;
  late final SessionManager session;
  late final SkillRuntime skills;
  late final AgentCore agent;
  late final List<ConversationEntry> blocks;
  late final List<PanelOverlay> panelStack;
  late final ConversationView conversation;
  late final ApprovalState approval;
  late final Lifecycle lifecycle;
  late final PanelController panels;
  late final DockManager dockManager;

  GlueConfig? config;
  LlmClientFactory? factory;

  SlashCommandContext get ctx => SlashCommandContext(
        configGetter: () => config,
        llmFactoryGetter: () => factory,
        agentGetter: () => agent,
        cwdGetter: () => environment.cwd,
        modelIdGetter: () => 'test/model',
        isIdleGetter: () => true,
        environment: environment,
        session: session,
        skills: skills,
        debug: null,
        dockManager: dockManager,
        autoApprovedTools: const <String>{},
        ensureSession: () {},
        resumeFromMeta: (_) => '',
        forkSession: (_, __) {},
        switchModel: (_) => '',
        conversation: conversation,
        approval: approval,
        lifecycle: lifecycle,
        panels: panels,
        commandsGetter: () => const <SlashCommand>[],
      );
}

void main() {
  group('RecapCommand', () {
    test('rejects extra args', () {
      final fx = _Fixture();
      final cmd = RecapCommand(fx.ctx);
      expect(cmd.execute(['extra']), 'Usage: /recap');
    });

    test('refuses when the conversation lacks a user/assistant pair', () {
      final fx = _Fixture();
      final cmd = RecapCommand(fx.ctx);
      expect(
          cmd.execute(const []), 'Not enough conversation yet to summarize.');
    });

    test('reports unavailability when no LLM factory is configured', () {
      final fx = _Fixture();
      fx.agent.addMessage(Message.user('hello'));
      fx.agent.addMessage(Message.assistant(text: 'hi'));
      // No GlueConfig and no LlmClientFactory → llm resolution short-circuits.
      final cmd = RecapCommand(fx.ctx);
      expect(cmd.execute(const []),
          'Recap unavailable: no model configured for summarization.');
    });
  });
}
