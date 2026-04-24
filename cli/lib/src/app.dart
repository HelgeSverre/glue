import 'dart:async';
import 'dart:io';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/subagents.dart';
import 'package:glue/src/catalog/model_display.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/config/approval_mode.dart';
import 'package:glue/src/config/constants.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/core/service_locator.dart';
import 'package:glue/src/input/file_expander.dart';
import 'package:glue/src/input/text_area_editor.dart';
import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/runtime/permission_gate.dart';
import 'package:glue/src/runtime/tool_permissions.dart';
import 'package:glue/src/providers/llm_client_factory.dart';
import 'package:glue/src/ui/rendering/ansi_utils.dart';
import 'package:glue/src/ui/rendering/block_renderer.dart';
import 'package:glue/src/runtime/app_events.dart';
import 'package:glue/src/runtime/app_mode.dart';
import 'package:glue/src/runtime/commands/command_host.dart';
import 'package:glue/src/runtime/input_router.dart';
import 'package:glue/src/runtime/commands/register_builtin_slash_commands.dart';
import 'package:glue/src/runtime/renderer.dart';
import 'package:glue/src/runtime/services/config.dart';
import 'package:glue/src/runtime/services/session.dart';
import 'package:glue/src/runtime/transcript.dart';
import 'package:glue/src/runtime/turn.dart';
import 'package:glue/src/runtime/controllers/chat_controller.dart';
import 'package:glue/src/ui/services/confirmations.dart';
import 'package:glue/src/runtime/controllers/model_controller.dart';
import 'package:glue/src/runtime/controllers/provider_controller.dart';
import 'package:glue/src/runtime/controllers/session_controller.dart';
import 'package:glue/src/runtime/controllers/skills_controller.dart';
import 'package:glue/src/runtime/controllers/system_controller.dart';
import 'package:glue/src/share/share_controller.dart';
import 'package:glue/src/session/session_manager.dart';
import 'package:glue/src/shell/bash_mode.dart';
import 'package:glue/src/shell/command_executor.dart';
import 'package:glue/src/shell/host_executor.dart';
import 'package:glue/src/shell/shell_completer.dart';
import 'package:glue/src/shell/shell_config.dart';
import 'package:glue/src/shell/shell_job_manager.dart';
import 'package:glue/src/skills/skill_activation.dart';
import 'package:glue/src/skills/skill_runtime.dart';
import 'package:glue/src/storage/session_store.dart';
import 'package:glue/src/terminal/layout.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/input/at_file_hint.dart';
import 'package:glue/src/ui/components/dock.dart';
import 'package:glue/src/ui/services/docks.dart';
import 'package:glue/src/ui/components/modal.dart';
import 'package:glue/src/ui/components/panel.dart';
import 'package:glue/src/ui/services/panels.dart';
import 'package:glue/src/shell/shell_autocomplete.dart';
import 'package:glue/src/commands/slash_autocomplete.dart';

part 'app/command_host_adapter.dart';
part 'app/event_router.dart';
part 'app/render_pipeline.dart';

// ---------------------------------------------------------------------------
// Main application controller
// ---------------------------------------------------------------------------

/// The main application controller.
///
/// Ties the terminal, layout, line editor, and agent together using an
/// event-driven architecture. Two independent streams (terminal input and
/// agent output) are merged into a single render cycle so the UI is never
/// blocked.
///
/// {@category Core}
class App {
  final Terminal terminal;
  final Layout layout;
  final TextAreaEditor editor;
  final Agent agent;
  final _events = StreamController<AppEvent>.broadcast();

  AppMode _mode = AppMode.idle;
  final Transcript _transcript = Transcript();
  final Renderer _renderer = Renderer();

  Turn? _currentTurn;
  StreamSubscription<SubagentUpdate>? _subagentSub;
  final _exitCompleter = Completer<void>();

  late final SlashCommandRegistry _commands;
  late final _AppCommandContext _commandContext;
  String _modelId;
  final Environment _environment;
  late final String _cwd;
  ConfirmModal? _activeModal;
  final List<AbstractPanel> _panelStack = [];
  late final Panels _panels;
  final DockManager _dockManager = DockManager();
  late final Docks _docks;
  final Subagents? _subagents;
  final LlmClientFactory? _llmFactory;
  GlueConfig? _config;
  final String? _systemPrompt;
  final CommandExecutor _executor;
  final ShellJobManager _jobManager;
  late final SlashAutocomplete _autocomplete;
  late final AtFileHint _atHint;
  late final ShellAutocomplete _shellComplete;
  late final SessionManager _sessionManager;
  late final Config _configService;
  late final Session _sessionService;
  late final BashMode _bash;
  late final InputRouter _input;

  final bool _startupContinue;
  final String? _startupPrompt;
  final bool _printMode;
  final bool _jsonMode;
  final String? _resumeSessionId;
  final Observability? _obs;
  final DebugController? _debugController;
  late final SkillRuntime _skillRuntime;
  ApprovalMode _approvalMode;

  App({
    required this.terminal,
    required this.layout,
    required this.editor,
    required this.agent,
    required String modelId,
    Subagents? subagents,
    LlmClientFactory? llmFactory,
    GlueConfig? config,
    String? systemPrompt,
    Set<String>? extraTrustedTools,
    SessionStore? sessionStore,
    CommandExecutor? executor,
    ShellJobManager? jobManager,
    bool startupContinue = false,
    String? startupPrompt,
    bool printMode = false,
    bool jsonMode = false,
    String? resumeSessionId,
    Observability? obs,
    DebugController? debugController,
    SkillRuntime? skillRuntime,
    Environment? environment,
  })  : _modelId = modelId,
        _environment = environment ?? Environment.detect(),
        _subagents = subagents,
        _llmFactory = llmFactory,
        _config = config,
        _systemPrompt = systemPrompt,
        _executor = executor ?? HostExecutor(const ShellConfig()),
        _jobManager = jobManager ??
            ShellJobManager(
              executor ?? HostExecutor(const ShellConfig()),
              obs: obs,
            ),
        _startupContinue = startupContinue,
        _startupPrompt = startupPrompt,
        _printMode = printMode,
        _jsonMode = jsonMode,
        _resumeSessionId = resumeSessionId,
        _obs = obs,
        _debugController = debugController,
        _approvalMode = config?.approvalMode ?? ApprovalMode.confirm {
    _cwd = _environment.cwd;
    _sessionManager = SessionManager(
      environment: _environment,
      sessionStore: sessionStore,
      observability: obs,
    );
    _panels = Panels(
      stack: _panelStack,
      render: _render,
    );
    _docks = Docks(_dockManager);
    _skillRuntime = skillRuntime ??
        SkillRuntime(
          cwd: _cwd,
          extraPathsProvider: () => _config?.skillPaths ?? const [],
          environment: _environment,
        );
    _configService = Config(
      read: () => _config,
      write: (next) => _config = next,
      environment: _environment,
      initialTrustedTools: {
        ...ToolPermissions.defaultTrustedTools,
        ...?extraTrustedTools,
      },
    );
    _sessionService = Session(
      manager: _sessionManager,
      agent: agent,
      transcript: _transcript,
      config: _configService,
      environment: _environment,
      modelIdProvider: () => _modelId,
      installDraft: editor.setText,
      llmFactory: _llmFactory,
    );
    _bash = BashMode(
      transcript: _transcript,
      executor: _executor,
      jobs: _jobManager,
      obs: _obs,
      setMode: (mode) => _mode = mode,
      stopSpinner: _stopSpinner,
      render: _render,
    );
    _initCommands();
    _autocomplete = SlashAutocomplete(_commands);
    _atHint = AtFileHint();
    _shellComplete = ShellAutocomplete(ShellCompleter());
    _input = InputRouter(
      editor: editor,
      layout: layout,
      transcript: _transcript,
      autocomplete: _autocomplete,
      atHint: _atHint,
      shellComplete: _shellComplete,
      commands: _commands,
      bash: _bash,
      panels: _panelStack,
      docks: _dockManager,
      getActiveModal: () => _activeModal,
      getMode: () => _mode,
      getApprovalMode: () => _approvalMode,
      setApprovalMode: (mode) => _approvalMode = mode,
      addEvent: _events.add,
      render: _render,
      doRender: _doRender,
      cancelAgent: _cancelAgent,
      requestExit: requestExit,
    );
  }

  PermissionGate get _permissionGate => PermissionGate(
        approvalMode: _approvalMode,
        trustedTools: _configService.trustedTools,
        tools: agent.tools,
        cwd: _cwd,
      );

  /// Convenience factory that creates a fully wired [App] with real
  /// LLM provider and subagent system.
  static Future<App> create({
    String? model,
    String? prompt,
    bool printMode = false,
    bool jsonMode = false,
    String? resumeSessionId,
    bool startupContinue = false,
    bool debug = false,
  }) async {
    final services = await ServiceLocator.create(model: model, debug: debug);

    return App(
      terminal: services.terminal,
      layout: services.layout,
      editor: services.editor,
      agent: services.agent,
      modelId: services.config.activeModel.modelId,
      subagents: services.subagents,
      llmFactory: services.llmFactory,
      config: services.config,
      systemPrompt: services.systemPrompt,
      extraTrustedTools: services.trustedTools,
      sessionStore: services.sessionStore,
      executor: services.executor,
      jobManager: services.jobManager,
      startupContinue: startupContinue,
      startupPrompt: prompt,
      printMode: printMode,
      jsonMode: jsonMode,
      resumeSessionId: resumeSessionId,
      obs: services.obs,
      debugController: services.debugController,
      skillRuntime: services.skillRuntime,
      environment: services.environment,
    );
  }

  /// Builds the prompt for print mode by combining stdin content and the
  /// user-supplied prompt string. Exposed as a static method for testing.
  static String buildPrintPrompt({String? prompt, String? stdinContent}) {
    return [
      if (stdinContent != null) '<stdin>\n$stdinContent</stdin>',
      if (prompt != null && prompt.isNotEmpty) prompt,
    ].join('\n\n');
  }

  String _shortenPath(String path) {
    final home = _environment.home;
    if (home.isNotEmpty && path.startsWith(home)) {
      return '~${path.substring(home.length)}';
    }
    return path;
  }

  /// Request a clean exit. Can be called from signal handlers.
  void requestExit() {
    _activeModal?.cancel();
    if (!_exitCompleter.isCompleted) _exitCompleter.complete();
  }

  /// Run the application event loop.
  ///
  /// Watches for SIGINT (forwarding to [requestExit] so the user can
  /// Ctrl+C out cleanly) and then enters raw / alt-screen mode. Processes
  /// events until the user requests an exit. Print mode branches off
  /// early — it doesn't need the interactive terminal setup at all.
  Future<void> run() async {
    final sigintSub =
        ProcessSignal.sigint.watch().listen((_) => requestExit());
    try {
      // Non-interactive print mode: stream response to stdout and exit.
      if (_printMode) {
        await _runPrintMode();
        return;
      }
      await _runInteractive();
    } finally {
      await sigintSub.cancel();
    }
  }

  Future<void> _runInteractive() async {

    terminal.enableRawMode();
    terminal.enableAltScreen();
    terminal.enableMouse();
    terminal.clearScreen();
    layout.apply();

    _transcript.blocks.add(ConversationEntry.system(
      '\x1b[33m◆\x1b[0m Glue v${AppConstants.version} — $_modelId\n'
      'Working directory: ${_shortenPath(_cwd)}\n'
      'Type /help for commands.',
    ));

    final termSub = terminal.events.listen(_input.handle);
    final appSub = _events.stream.listen(_handleAppEvent);
    _subagentSub = _subagents?.updates.listen((update) {
      if (_transcript.handleSubagentUpdate(update)) _render();
    });
    final jobSub = _jobManager.events.listen(_bash.handleJobEvent);

    _render();

    if (_resumeSessionId != null) {
      final sessions = _sessionManager.listSessions();
      if (_resumeSessionId.isEmpty) {
        _openResumePanel();
        _render();
      } else {
        final match = sessions.where((s) => s.id == _resumeSessionId).toList();
        if (match.isNotEmpty) {
          final result = _sessionService.resume(match.first);
          if (result.isNotEmpty) {
            _transcript.blocks.add(ConversationEntry.system(result));
          }
          _render();
        } else {
          _transcript.blocks.add(ConversationEntry.system(
            'Session $_resumeSessionId not found.',
          ));
          _render();
        }
      }
    } else if (_startupContinue) {
      final sessions = _sessionManager.listSessions();
      if (sessions.isNotEmpty) {
        final result = _sessionService.resume(sessions.first);
        if (result.isNotEmpty) {
          _transcript.blocks.add(ConversationEntry.system(result));
        }
        _render();
      } else {
        _transcript.blocks
            .add(ConversationEntry.system('No sessions to continue.'));
        _render();
      }
    }

    if (_startupPrompt case final prompt? when prompt.isNotEmpty) {
      _events.add(UserSubmit(prompt));
    }

    try {
      await _exitCompleter.future;
    } finally {
      // Stop all event sources before touching terminal state.
      _stopSpinner();
      // Dispose tools (closes browser sessions, containers, etc.).
      for (final tool in agent.tools.values) {
        try {
          await tool.dispose();
        } catch (_) {}
      }
      await _obs?.flush();
      await _obs?.close();
      await _sessionManager.closeCurrent();
      await jobSub.cancel();
      await _jobManager.shutdown();
      await termSub.cancel();
      await appSub.cancel();
      _currentTurn?.cancel();
      await _subagentSub?.cancel();
      await _events.close();
      terminal.disableMouse();
      terminal.resetScrollRegion();
      terminal.showCursor();
      terminal.write('\x1b[0m');
      terminal.disableAltScreen();
      terminal.disableRawMode();
      final sessionId = _sessionManager.currentSessionId;
      if (sessionId != null) {
        stdout
            .writeln('\n\x1b[33m◆\x1b[0m Holding it together till next time.');
        stdout.writeln('  \x1b[90m\$ glue --resume $sessionId\x1b[0m');
      }
      terminal.dispose();
    }
  }

  /// Non-interactive print mode: send prompt, stream response to stdout, exit.
  ///
  /// App prepares the prompt (optionally resuming a session and reading
  /// stdin), then hands off to [Turn.runPrint] for the actual turn
  /// lifecycle. App keeps ownership of the teardown (tool dispose, obs
  /// flush/close, session close) because those are app-lifetime concerns
  /// that wrap the turn.
  Future<void> _runPrintMode() async {
    if (_resumeSessionId != null) {
      if (_resumeSessionId.isEmpty) {
        stderr.writeln(
            'Error: --print does not support bare --resume; pass a session ID.');
        return;
      }
      final sessions = _sessionManager.listSessions();
      final match = sessions.where((s) => s.id == _resumeSessionId).toList();
      if (match.isEmpty) {
        stderr.writeln('Session $_resumeSessionId not found.');
        return;
      }
      _sessionManager.resumeSession(session: match.first, agent: agent);
    }

    String? stdinContent;
    if (!stdin.hasTerminal) {
      try {
        final buf = StringBuffer();
        String? line;
        while ((line = stdin.readLineSync()) != null) {
          buf.writeln(line);
        }
        final content = buf.toString().trimRight();
        if (content.isNotEmpty) stdinContent = content;
      } catch (_) {
        // Ignore stdin read errors.
      }
    }

    final prompt = _startupPrompt;
    if ((prompt == null || prompt.isEmpty) && stdinContent == null) {
      stderr.writeln('Error: --print requires a prompt.');
      return;
    }

    final fullPrompt =
        App.buildPrintPrompt(prompt: prompt, stdinContent: stdinContent);
    final expanded = expandFileRefs(fullPrompt);

    final turn = _makeTurn();
    try {
      await turn.runPrint(expandedPrompt: expanded, jsonMode: _jsonMode);
    } finally {
      for (final tool in agent.tools.values) {
        try {
          await tool.dispose();
        } catch (_) {}
      }
      await _obs?.flush();
      await _obs?.close();
      await _sessionManager.closeCurrent();
    }
  }

  /// Construct a fresh [Turn] wired to App's current state. Interactive and
  /// print paths share this factory so their wiring stays in sync.
  Turn _makeTurn() => Turn(
        agent: agent,
        transcript: _transcript,
        renderer: _renderer,
        session: _sessionService,
        config: _configService,
        obs: _obs,
        permissionGateFactory: () => _permissionGate,
        modelIdProvider: () => _modelId,
        setMode: (mode) => _mode = mode,
        setActiveModal: (modal) => _activeModal = modal,
        getActiveModal: () => _activeModal,
        render: _render,
        onTurnComplete: _sessionService.onTurnComplete,
      );

  /// Cleanly shut down the application.
  void shutdown() {
    requestExit();
  }

  // ── Slash commands ──────────────────────────────────────────────────────

  void _initCommands() {
    _commandContext = _AppCommandContext(this);
    _commands = buildBuiltinSlashCommands(_commandContext);
  }

  void _openResumePanel() {
    _commandContext.sessions.openResumePanel();
  }

  Future<void> _activateSkillFromUi(String skillName) async {
    try {
      final activation = await activateSkillIntoConversation(
        agent: agent,
        skillName: skillName,
      );

      _sessionService.ensureStore();
      _sessionService.logEvent('tool_call', {
        'name': 'skill',
        'arguments': {'name': skillName},
      });
      _sessionService.logEvent('tool_result', {
        'name': 'skill',
        'content': activation.content,
      });

      _transcript.blocks
          .add(ConversationEntry.toolCall('skill', {'name': skillName}));
      _transcript.blocks
          .add(ConversationEntry.toolResult(activation.content));
    } on SkillActivationError catch (e) {
      _transcript.postNotice(e.message);
    } catch (e) {
      _transcript.postNotice('Error activating skill "$skillName": $e');
    }
  }

  // ── App event handling ──────────────────────────────────────────────────

  void _handleAppEvent(AppEvent event) {
    _handleAppEventImpl(this, event);
  }

  // ── Agent interaction ──────────────────────────────────────────────────

  void _startAgent(String displayMessage, {String? expandedMessage}) {
    _currentTurn = _makeTurn()
      ..run(displayMessage, expandedMessage: expandedMessage);
  }

  void _cancelAgent() => _currentTurn?.cancel();

  // ── Rendering ──────────────────────────────────────────────────────────

  void _stopSpinner() => _renderer.stopSpinner();

  void _render() => _renderer.schedule(_doRender);

  void _doRender() {
    _doRenderImpl(this);
  }
}
