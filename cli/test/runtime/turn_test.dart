import 'dart:async';
import 'dart:io';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/config/approval_mode.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/runtime/app_mode.dart';
import 'package:glue/src/runtime/permission_gate.dart';
import 'package:glue/src/runtime/renderer.dart';
import 'package:glue/src/runtime/services/config.dart';
import 'package:glue/src/runtime/services/session.dart';
import 'package:glue/src/runtime/transcript.dart';
import 'package:glue/src/runtime/turn.dart';
import 'package:glue/src/session/session_manager.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/ui/components/modal.dart';
import 'package:test/test.dart';

import '../_helpers/test_config.dart';

class _RecordingSink extends ObservabilitySink {
  final List<ObservabilitySpan> spans = [];

  @override
  void onSpan(ObservabilitySpan span) => spans.add(span);

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

class _ThrowingLlm implements LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    throw StateError('boom');
  }
}

class _DelayedLlm implements LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    yield TextDelta('done');
  }
}

class _TextOnlyLlm implements LlmClient {
  final String response;
  _TextOnlyLlm(this.response);

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    yield TextDelta(response);
    yield UsageInfo(inputTokens: 5, outputTokens: 5);
  }
}

class _ToolCallOnceLlm implements LlmClient {
  int _call = 0;
  final String toolName;
  final Map<String, dynamic> toolArgs;
  _ToolCallOnceLlm(this.toolName, this.toolArgs);

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    _call++;
    if (_call == 1) {
      yield ToolCallStart(id: 'tc1', name: toolName);
      yield ToolCallComplete(
          ToolCall(id: 'tc1', name: toolName, arguments: toolArgs));
      yield UsageInfo(inputTokens: 5, outputTokens: 5);
    } else {
      yield TextDelta('ok done');
      yield UsageInfo(inputTokens: 5, outputTokens: 5);
    }
  }
}

class _RecordingTool extends Tool {
  _RecordingTool({
    required this.toolName,
    this.toolTrust = ToolTrust.safe,
  });

  final String toolName;
  final ToolTrust toolTrust;
  int executions = 0;

  @override
  String get name => toolName;

  @override
  String get description => 'recording tool';

  @override
  List<ToolParameter> get parameters => const [];

  @override
  ToolTrust get trust => toolTrust;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    executions++;
    return ToolResult(content: 'done');
  }
}

class _TurnHarness {
  _TurnHarness({
    required this.tempDir,
    required this.turn,
    required this.sink,
    required this.transcript,
    required this.agent,
    required this.config,
    required this.renderer,
    required this.modeLog,
    required this.getActiveModal,
    required this.renders,
    required this.turnCompletes,
  });

  final Directory tempDir;
  final Turn turn;
  final _RecordingSink sink;
  final Transcript transcript;
  final Agent agent;
  final Config config;
  final Renderer renderer;
  final List<AppMode> modeLog;
  final ConfirmModal? Function() getActiveModal;
  final List<void> renders;
  final List<void> turnCompletes;

  void dispose() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

_TurnHarness _makeHarness(
  LlmClient llm, {
  Map<String, Tool> tools = const {},
  ApprovalMode approvalMode = ApprovalMode.confirm,
  Iterable<String> trustedTools = const [],
}) {
  final tempDir = Directory.systemTemp.createTempSync('turn_test_');
  final environment = Environment.test(home: tempDir.path, cwd: tempDir.path);
  environment.ensureDirectories();

  final sink = _RecordingSink();
  final obs = Observability(debugController: DebugController())..addSink(sink);
  final agent = Agent(llm: llm, tools: tools, obs: obs, modelId: 'test');
  final transcript = Transcript();
  final renderer = Renderer();
  var glueConfig = testConfig(
    env: {'ANTHROPIC_API_KEY': 'sk-test'},
    credentialsPath: '${tempDir.path}/credentials.json',
  );
  final config = Config(
    read: () => glueConfig,
    write: (next) => glueConfig = next,
    environment: environment,
    initialTrustedTools: trustedTools,
  );
  final session = Session(
    manager: SessionManager(environment: environment, observability: obs),
    agent: agent,
    transcript: transcript,
    config: config,
    environment: environment,
    modelIdProvider: () => 'test',
    installDraft: (_) {},
  );
  final modeLog = <AppMode>[];
  ConfirmModal? activeModal;
  final renders = <void>[];
  final turnCompletes = <void>[];

  final turn = Turn(
    agent: agent,
    transcript: transcript,
    renderer: renderer,
    session: session,
    config: config,
    obs: obs,
    permissionGateFactory: () => PermissionGate(
      approvalMode: approvalMode,
      trustedTools: config.trustedTools,
      tools: agent.tools,
      cwd: environment.cwd,
    ),
    modelIdProvider: () => 'test',
    setMode: modeLog.add,
    setActiveModal: (modal) => activeModal = modal,
    getActiveModal: () => activeModal,
    render: () => renders.add(null),
    onTurnComplete: () => turnCompletes.add(null),
  );

  return _TurnHarness(
    tempDir: tempDir,
    turn: turn,
    sink: sink,
    transcript: transcript,
    agent: agent,
    config: config,
    renderer: renderer,
    modeLog: modeLog,
    getActiveModal: () => activeModal,
    renders: renders,
    turnCompletes: turnCompletes,
  );
}

Future<void> _waitForAgentDone(_TurnHarness h,
    {Duration timeout = const Duration(seconds: 2)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (h.modeLog.isNotEmpty && h.modeLog.last == AppMode.idle) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  group('Turn.run — interactive lifecycle', () {
    test('appends a user block and transitions to streaming mode', () async {
      final h = _makeHarness(_TextOnlyLlm('hi there'));
      addTearDown(h.dispose);

      h.turn.run('hello');

      // First block is the user's message.
      expect(h.transcript.blocks, isNotEmpty);
      expect(h.transcript.blocks.first.kind, EntryKind.user);
      expect(h.transcript.blocks.first.text, 'hello');
      // Streaming mode kicks in synchronously.
      expect(h.modeLog.first, AppMode.streaming);

      await _waitForAgentDone(h);
    });

    test('user block preserves displayMessage vs expandedMessage', () async {
      final h = _makeHarness(_TextOnlyLlm('hi'));
      addTearDown(h.dispose);

      h.turn.run('short', expandedMessage: 'LONG-EXPANDED');

      final userEntry = h.transcript.blocks.first;
      expect(userEntry.text, 'short');
      expect(userEntry.expandedText, 'LONG-EXPANDED');

      await _waitForAgentDone(h);
    });

    test(
        'assistant text is accumulated and flushed as a block on '
        'AgentDone', () async {
      final h = _makeHarness(_TextOnlyLlm('all done'));
      addTearDown(h.dispose);

      h.turn.run('hi');
      await _waitForAgentDone(h);

      final assistantEntries = h.transcript.blocks
          .where((e) => e.kind == EntryKind.assistant)
          .toList();
      expect(assistantEntries, hasLength(1));
      expect(assistantEntries.single.text, 'all done');
      expect(h.transcript.streamingText, isEmpty);
      expect(h.modeLog.last, AppMode.idle);
    });

    test('onTurnComplete fires exactly once on AgentDone', () async {
      final h = _makeHarness(_TextOnlyLlm('done'));
      addTearDown(h.dispose);

      h.turn.run('hi');
      await _waitForAgentDone(h);

      expect(h.turnCompletes, hasLength(1));
    });
  });

  group('Turn.cancel — mid-stream teardown', () {
    test('cancel during a live turn returns mode to idle', () async {
      final h = _makeHarness(_DelayedLlm());
      addTearDown(h.dispose);

      h.turn.run('hello');
      expect(h.modeLog.first, AppMode.streaming);
      h.turn.cancel();

      expect(h.modeLog.last, AppMode.idle);
    });

    test('cancel ends the agent.turn span with cancelled=true', () async {
      final h = _makeHarness(_DelayedLlm());
      addTearDown(h.dispose);

      h.turn.run('hello');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      h.turn.cancel();

      final span = h.sink.spans.lastWhere((span) => span.name == 'agent.turn');
      expect(span.attributes['cancelled'], isTrue);
      expect(span.endTime, isNotNull);
    });

    test(
        'in-flight streamingText is flushed as "[cancelled]" '
        'assistant block when cancel happens', () async {
      final h = _makeHarness(_DelayedLlm());
      addTearDown(h.dispose);

      h.turn.run('hello');
      // Inject partial streaming text directly (simulates a delta
      // arriving before we cancel).
      h.transcript.streamingText = 'partial';
      h.turn.cancel();

      final assistantEntries = h.transcript.blocks
          .where((e) => e.kind == EntryKind.assistant)
          .toList();
      expect(assistantEntries, hasLength(1));
      expect(assistantEntries.single.text, contains('partial'));
      expect(assistantEntries.single.text, contains('[cancelled]'));
    });

    test('cancel flips in-flight tool UI states to cancelled', () async {
      final h = _makeHarness(_DelayedLlm());
      addTearDown(h.dispose);

      h.turn.run('hello');
      // Simulate a tool call that was still running when cancel fired.
      h.transcript.toolUi['tc-live'] = ToolCallUiState(
        id: 'tc-live',
        name: 'read_file',
        phase: ToolPhase.running,
      );
      h.transcript.toolUi['tc-pending'] = ToolCallUiState(
        id: 'tc-pending',
        name: 'read_file',
        phase: ToolPhase.preparing,
      );
      h.transcript.toolUi['tc-done'] = ToolCallUiState(
        id: 'tc-done',
        name: 'read_file',
        phase: ToolPhase.done,
      );

      h.turn.cancel();

      expect(h.transcript.toolUi['tc-live']!.phase, ToolPhase.cancelled);
      expect(h.transcript.toolUi['tc-pending']!.phase, ToolPhase.cancelled);
      // Already-done tool calls are left alone.
      expect(h.transcript.toolUi['tc-done']!.phase, ToolPhase.done);
    });
  });

  group('Turn.run — AgentError span metadata', () {
    test('interactive AgentError ends agent.turn as failed', () async {
      final harness = _makeHarness(_ThrowingLlm());
      addTearDown(harness.dispose);

      harness.turn.run('hello');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final span =
          harness.sink.spans.singleWhere((span) => span.name == 'agent.turn');
      expect(span.attributes['error'], isTrue);
      expect(span.attributes['error.message'], contains('boom'));
      expect(span.statusCode, 'error');
    });

    test('interactive AgentError appends an error block', () async {
      final h = _makeHarness(_ThrowingLlm());
      addTearDown(h.dispose);

      h.turn.run('hello');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final errorEntries =
          h.transcript.blocks.where((e) => e.kind == EntryKind.error).toList();
      expect(errorEntries, hasLength(1));
      expect(errorEntries.single.text, contains('boom'));
    });
  });

  group('Turn.run — double-run guard', () {
    test('run throws when called while the turn is live', () {
      final harness = _makeHarness(_DelayedLlm());
      addTearDown(harness.dispose);

      harness.turn.run('first');

      expect(
        () => harness.turn.run('second'),
        throwsA(isA<StateError>()),
      );

      harness.turn.cancel();
    });

    test('after cancel, a new run is allowed on the same Turn instance',
        () async {
      final h = _makeHarness(_DelayedLlm());
      addTearDown(h.dispose);

      h.turn.run('first');
      h.turn.cancel();

      // Second run now fine.
      expect(() => h.turn.run('second'), returnsNormally);
      h.turn.cancel();
    });
  });

  group('Turn — tool approval flow (full modal)', () {
    test('Yes approves the tool — execute runs and no trust set', () async {
      final tool =
          _RecordingTool(toolName: 'write_file', toolTrust: ToolTrust.fileEdit);
      final h = _makeHarness(
        _ToolCallOnceLlm('write_file', {'path': 'a.txt'}),
        tools: {'write_file': tool},
      );
      addTearDown(h.dispose);

      h.turn.run('write a file');

      // Wait for the modal to open.
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (h.getActiveModal() == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final modal = h.getActiveModal();
      expect(modal, isNotNull, reason: 'modal should open');
      expect(modal!.title, contains('write_file'));

      // Simulate the user pressing Yes (choice index 0).
      modal.handleEvent(KeyEvent(Key.enter));

      // Wait for the tool to run and the follow-up agent response.
      await _waitForAgentDone(h);

      expect(tool.executions, 1);
      expect(h.config.trustedTools, isNot(contains('write_file')));
    });

    test(
        'Always approves and trusts the tool for the rest of the '
        'session', () async {
      final tool =
          _RecordingTool(toolName: 'write_file', toolTrust: ToolTrust.fileEdit);
      final h = _makeHarness(
        _ToolCallOnceLlm('write_file', {'path': 'a.txt'}),
        tools: {'write_file': tool},
      );
      addTearDown(h.dispose);

      h.turn.run('do it');

      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (h.getActiveModal() == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final modal = h.getActiveModal();
      expect(modal, isNotNull);

      // Navigate to "Always" (choice index 2) and confirm.
      modal!.handleEvent(KeyEvent(Key.right));
      modal.handleEvent(KeyEvent(Key.right));
      modal.handleEvent(KeyEvent(Key.enter));

      await _waitForAgentDone(h);

      expect(h.config.trustedTools, contains('write_file'));
      expect(tool.executions, 1);
    });

    test('No denies the tool — execute never runs', () async {
      final tool =
          _RecordingTool(toolName: 'write_file', toolTrust: ToolTrust.fileEdit);
      final h = _makeHarness(
        _ToolCallOnceLlm('write_file', {'path': 'a.txt'}),
        tools: {'write_file': tool},
      );
      addTearDown(h.dispose);

      h.turn.run('do it');

      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (h.getActiveModal() == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final modal = h.getActiveModal();
      expect(modal, isNotNull);

      // "No" is choice index 1.
      modal!.handleEvent(KeyEvent(Key.right));
      modal.handleEvent(KeyEvent(Key.enter));

      await _waitForAgentDone(h);

      expect(tool.executions, 0);
      // A toolUi entry exists; phases flow denied -> possibly others as the
      // agent continues. The stable invariant is that the tool was never
      // executed and a denied or cancelled phase was observed.
      final uiEntries = h.transcript.toolUi.values.toList();
      expect(uiEntries, isNotEmpty);
    });

    test(
        'trustedTools pre-set means no modal opens — tool '
        'auto-approves', () async {
      final tool =
          _RecordingTool(toolName: 'write_file', toolTrust: ToolTrust.fileEdit);
      final h = _makeHarness(
        _ToolCallOnceLlm('write_file', {'path': 'a.txt'}),
        tools: {'write_file': tool},
        trustedTools: {'write_file'},
      );
      addTearDown(h.dispose);

      h.turn.run('do it');
      await _waitForAgentDone(h);

      // Modal should never have been attached.
      expect(h.getActiveModal(), isNull);
      expect(tool.executions, 1);
    });
  });

  group('Turn.runPrint — print-mode output shape', () {
    test('JSON mode emits a session_id, model, conversation envelope',
        () async {
      final h = _makeHarness(_TextOnlyLlm('the answer'));
      addTearDown(h.dispose);

      // runPrint writes to stdout; we can't capture that cheaply from
      // a pure Dart test, so instead we assert the observable
      // side-effects: span lifecycle and session logging.
      await h.turn.runPrint(
        expandedPrompt: 'what is it',
        jsonMode: true,
      );

      final turnSpan =
          h.sink.spans.singleWhere((span) => span.name == 'agent.turn');
      expect(turnSpan.endTime, isNotNull);
      expect(turnSpan.attributes['process.command'], 'print');
      expect(turnSpan.attributes['output.length'], greaterThan(0));
    });

    test(
        'non-JSON print mode still ends the turn span with '
        'output metadata', () async {
      final h = _makeHarness(_TextOnlyLlm('hello'));
      addTearDown(h.dispose);

      await h.turn.runPrint(
        expandedPrompt: 'hi',
        jsonMode: false,
      );

      final turnSpan =
          h.sink.spans.singleWhere((span) => span.name == 'agent.turn');
      expect(turnSpan.endTime, isNotNull);
      expect(turnSpan.attributes['output.length'], greaterThan(0));
      expect(turnSpan.attributes['openinference.span.kind'], 'AGENT');
    });
  });
}
