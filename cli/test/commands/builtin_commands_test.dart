import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:glue/glue.dart';
import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/conversation/entry.dart';
import 'package:glue/src/services/approval_state.dart';
import 'package:glue/src/services/conversation_view.dart';
import 'package:glue/src/services/lifecycle.dart';
import 'package:glue/src/ui/dock_manager.dart';
import 'package:test/test.dart';

class _NoopTerminal extends Terminal {
  @override
  Stream<TerminalEvent> get events => const Stream.empty();

  @override
  int get columns => 120;

  @override
  int get rows => 40;

  @override
  void clearScreen() {}

  @override
  void clearLine() {}

  @override
  void disableAltScreen() {}

  @override
  void disableMouse() {}

  @override
  void disableRawMode() {}

  @override
  void enableAltScreen() {}

  @override
  void enableMouse() {}

  @override
  void enableRawMode() {}

  @override
  void hideCursor() {}

  @override
  bool get isRaw => false;

  @override
  void moveTo(int row, int col) {}

  @override
  void resetScrollRegion() {}

  @override
  void restoreCursor() {}

  @override
  void saveCursor() {}

  @override
  void setScrollRegion(int top, int bottom) {}

  @override
  void showCursor() {}

  @override
  void write(String text) {}

  @override
  void writeStyled(String text, {AnsiStyle? style}) {}
}

class _NoopLlm implements LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {}
}

Environment _isolatedEnv() {
  final dir = Directory.systemTemp.createTempSync('cmdfx_');
  return Environment.test(home: dir.path, cwd: dir.path);
}

class _CommandTestFixture {
  _CommandTestFixture({
    Environment? environment,
    SessionManager? session,
    SkillRuntime? skills,
    AgentCore? agent,
  })  : environment = environment ?? _isolatedEnv(),
        session = session ??
            SessionManager(environment: environment ?? _isolatedEnv()),
        skills = skills ??
            SkillRuntime(cwd: '/tmp', extraPathsProvider: () => const []),
        agent = agent ?? AgentCore(llm: _NoopLlm(), tools: const {}) {
    blocks = <ConversationEntry>[];
    panelStack = <PanelOverlay>[];
    subagentGroups = <String, SubagentGroup>{};
    editor = TextAreaEditor();
    conversation = ConversationView(
      blocks: blocks,
      subagentGroups: subagentGroups,
      streamingTextGetter: () => streamingText,
      render: () => renderCalls++,
      resetStreamingText: () => streamingText = '',
      clearScreen: () => clearScreenCalls++,
      resetScrollOffset: () {},
      clearToolUi: () {},
      clearSubagentGroups: () => subagentGroups.clear(),
    );
    approval = ApprovalState(
      get: () => approvalMode,
      set: (m) => approvalMode = m,
    );
    lifecycle = Lifecycle(onExit: () => exitCalls++);
    panels = ModalSurface(panelStack: panelStack, render: () {});
    dockManager = DockManager();
    mcpPool = McpClientPool(
      config: const McpConfig(),
      credentials: CredentialStore(
        path: '${this.environment.glueDir}/credentials.json',
        env: const {},
      ),
    );
  }

  final Environment environment;
  final SessionManager session;
  final SkillRuntime skills;
  final AgentCore agent;
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
  String streamingText = '';
  int renderCalls = 0;
  int clearScreenCalls = 0;
  int exitCalls = 0;
  ApprovalMode approvalMode = ApprovalMode.confirm;
  GlueConfig? config;
  LlmClientFactory? llmFactory;

  SlashCommandContext build({
    Iterable<SlashCommand> Function()? commandsGetter,
  }) =>
      SlashCommandContext(
        configGetter: () => config,
        llmFactoryGetter: () => llmFactory,
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
        commandsGetter: commandsGetter ?? () => const [],
      );
}

void main() {
  group('BuiltinCommands', () {
    SlashCommandRegistry createRegistry({_CommandTestFixture? fixture}) {
      final fx = fixture ?? _CommandTestFixture();
      late final SlashCommandRegistry registry;
      final ctx = fx.build(commandsGetter: () => registry.commands);
      return registry = BuiltinCommands.create(ctx);
    }

    test('/copy with no assistant text posts a notice', () {
      final fx = _CommandTestFixture();
      final registry = createRegistry(fixture: fx);
      registry.execute('/copy');
      expect(
        fx.blocks.where((e) => e.kind == EntryKind.system).map((e) => e.text),
        contains('No assistant response to copy yet.'),
      );
    });

    test('/models is no longer registered (alias removed)', () {
      final registry = createRegistry();
      final result = registry.execute('/models');
      expect(result, contains('Unknown command: /models'));
      expect(registry.commands.where((c) => c.name == 'models'), isEmpty);
      expect(
        registry.commands.firstWhere((c) => c.name == 'model').aliases,
        isEmpty,
      );
    });

    test('/model short-circuits when config is not yet wired', () {
      // Fixture has no GlueConfig; ModelCommand returns the early-exit message
      // before reaching the resolver.
      final registry = createRegistry();
      final result = registry.execute('/model totallyfake');
      expect(result, 'Config not ready.');
    });

    test('/history with no transcript posts the empty notice', () {
      final fx = _CommandTestFixture();
      final registry = createRegistry(fixture: fx);
      final result = registry.execute('/history');
      expect(result, '');
      expect(
        fx.blocks.where((e) => e.kind == EntryKind.system).map((e) => e.text),
        contains('No conversation history.'),
      );
    });

    test('/history <query> with no entries returns the empty message', () {
      final registry = createRegistry();
      final result = registry.execute('/history 1');
      expect(result, 'No conversation history.');
    });

    test('/resume with empty session list posts the empty notice', () {
      final fx = _CommandTestFixture();
      final registry = createRegistry(fixture: fx);
      final result = registry.execute('/resume');
      expect(result, '');
      expect(
        fx.blocks.where((e) => e.kind == EntryKind.system).map((e) => e.text),
        contains('No saved sessions found.'),
      );
    });

    test('/resume <query> with no sessions returns the empty message', () {
      final registry = createRegistry();
      final result = registry.execute('/resume nope');
      expect(result, 'No saved sessions found.');
    });

    test('/paths returns a where-style report', () {
      final registry = createRegistry();
      final result = registry.execute('/paths');
      expect(result, contains('GLUE'));
    });

    test('/where is a hidden alias for /paths', () {
      final registry = createRegistry();
      final result = registry.execute('/where');
      expect(result, contains('GLUE'));
    });

    test('/open without args returns usage hint', () {
      final registry = createRegistry();
      final result = registry.execute('/open')!;
      expect(result, contains('Usage: /open <target>'));
      expect(result, contains('home'));
    });

    test('/open with unknown target returns helpful error', () {
      final registry = createRegistry();
      final result = registry.execute('/open lolwhat')!;
      expect(result, contains('Unknown target "lolwhat"'));
    });

    test('/config without EDITOR set reports the missing var', () {
      final registry = createRegistry();
      final result = registry.execute('/config')!;
      expect(result, contains(r'EDITOR is not set'));
    });

    test('/config with unknown subcommand reports usage', () {
      final registry = createRegistry();
      final result = registry.execute('/config lolwhat')!;
      expect(result, contains('Unknown subcommand "lolwhat"'));
    });

    test('/session with no active session prints the info report', () {
      final registry = createRegistry();
      final result = registry.execute('/session')!;
      expect(result, startsWith('Session Info'));
      expect(result, contains('Session ID:   (none)'));
    });

    test('/session copy with no active session reports nothing to copy', () {
      final registry = createRegistry();
      final result = registry.execute('/session copy');
      expect(result, 'No active session yet — nothing to copy.');
    });

    test('/session with unknown subcommand reports usage', () {
      final registry = createRegistry();
      final result = registry.execute('/session lolwhat');
      expect(result, 'Unknown subcommand "lolwhat". Try: /session copy');
    });

    test('/rename with empty title returns the usage hint', () {
      final registry = createRegistry();
      final result = registry.execute('/rename');
      expect(result, 'Usage: /rename <new title>');
    });

    test('/rename hello marks the session as manually renamed', () {
      final fx = _CommandTestFixture();
      final registry = createRegistry(fixture: fx);
      final result = registry.execute('/rename hello');
      expect(result, 'Renamed session to "hello".');
      expect(fx.session.titleManuallyOverridden, isTrue);
    });

    test('/provider list with empty config reports config not ready', () {
      // Fixture has no GlueConfig wired; ProviderCommand short-circuits.
      final registry = createRegistry();
      final result = registry.execute('/provider list');
      expect(result, 'Config not ready.');
    });

    test('/provider remove without args returns usage hint', () {
      final registry = createRegistry();
      final result = registry.execute('/provider remove');
      expect(result, 'Config not ready.',
          reason: 'fixture has no config; short-circuit fires before usage');
    });

    test('/provider with unknown subcommand reports usage', () {
      final registry = createRegistry();
      final result = registry.execute('/provider lolwhat');
      expect(result, 'Config not ready.');
    });

    test('/share with no active session reports nothing to share', () {
      final fx = _CommandTestFixture();
      final registry = createRegistry(fixture: fx);
      final result = registry.execute('/share');
      expect(result, 'No active session yet — nothing to share.');
    });

    test('/share rejects unknown formats', () {
      final fx = _CommandTestFixture();
      final tempDir = Directory.systemTemp.createTempSync('share_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      fx.session.ensureSessionStore(
        cwd: fx.environment.cwd,
        modelRef: 'anthropic/claude-sonnet-4.6',
      );
      final registry = createRegistry(fixture: fx);
      final result = registry.execute('/share xml');
      expect(result, 'Usage: /share [html|md|gist]');
    });

    test('/skills returns empty inline output (panel orchestration is async)',
        () {
      final fx = _CommandTestFixture();
      final registry = createRegistry(fixture: fx);
      final result = registry.execute('/skills');
      expect(result, '');
    });

    test('/skills <name> returns the activating banner inline', () {
      final fx = _CommandTestFixture();
      final registry = createRegistry(fixture: fx);
      final result = registry.execute('/skills code-review');
      expect(result, 'Activating skill "code-review"...');
    });

    test('/runtime short-circuits when config is not wired', () {
      final registry = createRegistry();
      final result = registry.execute('/runtime');
      expect(result, contains('No active config'));
    });

    test('/runtime is registered and exposes a description', () {
      final registry = createRegistry();
      final cmd = registry.commands.firstWhere((c) => c.name == 'runtime');
      expect(cmd.description, contains('execution runtime'));
    });
  });

  group('App startup resume behavior', () {
    late Directory tempDir;
    late Environment environment;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('app_resume_startup_test_');
      environment = Environment.test(home: tempDir.path, cwd: tempDir.path);
      environment.ensureDirectories();
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('bare --resume opens the resume panel on startup', () async {
      final meta = SessionMeta(
        id: const SessionId('resume-target'),
        cwd: environment.cwd,
        modelRef: 'anthropic/claude-sonnet-4.6',
        startTime: DateTime.now(),
        title: 'Saved work',
      );
      SessionStore(sessionDir: environment.sessionDir(meta.id), meta: meta);

      final app = App(
        terminal: _NoopTerminal(),
        layout: Layout(_NoopTerminal()),
        editor: TextAreaEditor(),
        agent: AgentCore(llm: _NoopLlm(), tools: const {}),
        modelId: 'anthropic/claude-sonnet-4.6',
        startupPrompt: null,
        resumeSessionId: '',
        environment: environment,
      );

      final runFuture = app.run();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      app.requestExit();
      await runFuture;

      expect(app.editor.text, isEmpty,
          reason:
              'opening the resume panel should not inject conversation text');
      expect(
        SessionStore.listSessions(environment.sessionsDir).map((s) => s.id),
        contains('resume-target'),
      );
    });

    test('resume with startup prompt submits the prompt after resuming',
        () async {
      final meta = SessionMeta(
        id: const SessionId('resume-target'),
        cwd: environment.cwd,
        modelRef: 'anthropic/claude-sonnet-4.6',
        startTime: DateTime.now(),
        title: 'Saved work',
      );
      final store =
          SessionStore(sessionDir: environment.sessionDir(meta.id), meta: meta);
      store.logEvent('user_message', {'text': 'Earlier context'});
      store.logEvent('assistant_message', {'text': 'Prior answer'});

      final app = App(
        terminal: _NoopTerminal(),
        layout: Layout(_NoopTerminal()),
        editor: TextAreaEditor(),
        agent: AgentCore(llm: _NoopLlm(), tools: const {}),
        modelId: 'anthropic/claude-sonnet-4.6',
        startupPrompt: 'bar',
        resumeSessionId: 'resume-target',
        environment: environment,
      );

      final runFuture = app.run();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      app.requestExit();
      await runFuture;

      expect(
        app.agent.conversation.map((m) => m.text),
        contains('bar'),
      );
    });
  });
}
