import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/terminal/layout.dart';
import 'package:glue/src/input/line_editor.dart' show InputAction;
import 'package:glue/src/input/text_area_editor.dart';
import 'package:glue/src/input/streaming_input_handler.dart';
import 'package:glue/src/input/file_expander.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/agent_manager.dart';
import 'package:glue/src/commands/builtin_commands.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/config/constants.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/config/model_registry.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/core/service_locator.dart';
import 'package:glue/src/config/permission_mode.dart';
import 'package:glue/src/dev/devtools.dart';
import 'package:glue/src/llm/llm_factory.dart';
import 'package:glue/src/llm/title_generator.dart';
import 'package:glue/src/orchestrator/permission_gate.dart';
import 'package:glue/src/orchestrator/tool_permissions.dart';
import 'package:glue/src/rendering/block_renderer.dart';
import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/rendering/mascot.dart';
import 'package:glue/src/shell/command_executor.dart';
import 'package:glue/src/shell/host_executor.dart';
import 'package:glue/src/shell/shell_config.dart';
import 'package:glue/src/shell/shell_job_manager.dart';
import 'package:glue/src/shell/shell_completer.dart';
import 'package:glue/src/session/session_manager.dart';
import 'package:glue/src/storage/config_store.dart';
import 'package:glue/src/storage/session_state.dart';
import 'package:glue/src/storage/session_store.dart';
import 'package:glue/src/skills/skill_registry.dart';
import 'package:glue/src/skills/skill_activation.dart';
import 'package:glue/src/skills/skill_runtime.dart';
import 'package:glue/src/ui/modal.dart';
import 'package:glue/src/ui/dock_manager.dart';
import 'package:glue/src/ui/panel_modal.dart';
import 'package:glue/src/ui/panel_controller.dart';
import 'package:glue/src/ui/skills_docked_panel.dart';
import 'package:glue/src/ui/at_file_hint.dart';
import 'package:glue/src/ui/shell_autocomplete.dart';
import 'package:glue/src/ui/slash_autocomplete.dart';
import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/observability/observability.dart';

part 'app_event_router.dart';
part 'app_agent_orchestration.dart';
part 'app_command_helpers.dart';
part 'app_events.dart';
part 'app_models.dart';
part 'app_render_pipeline.dart';
part 'app_session_runtime.dart';
part 'app_splash_runtime.dart';
part 'app_shell_runtime.dart';
part 'app_subagent_updates.dart';
part 'app_terminal_event_router.dart';

// ---------------------------------------------------------------------------
// Application state
// ---------------------------------------------------------------------------

/// Top-level application mode.
///
/// {@category Core}
enum AppMode {
  /// Waiting for user input.
  idle,

  /// The LLM is streaming a response.
  streaming,

  /// A tool is currently executing.
  toolRunning,

  /// Waiting for user to approve a tool invocation.
  confirming,

  /// A bash command is currently executing.
  bashRunning,
}

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
  final AgentCore agent;
  final _events = StreamController<AppEvent>.broadcast();

  AppMode _mode = AppMode.idle;
  final List<_ConversationEntry> _blocks = [];
  final Map<String, _ToolCallUiState> _toolUi = {};
  int _scrollOffset = 0;

  static const _spinnerFrames = [
    '⠋',
    '⠙',
    '⠹',
    '⠸',
    '⠼',
    '⠴',
    '⠦',
    '⠧',
    '⠇',
    '⠏'
  ];
  int _spinnerFrame = 0;
  Timer? _spinnerTimer;
  String _streamingText = '';
  StreamSubscription<AgentEvent>? _agentSub;
  StreamSubscription<SubagentUpdate>? _subagentSub;
  final _exitCompleter = Completer<void>();

  late final SlashCommandRegistry _commands;
  String _modelId;
  final Environment _environment;
  late final String _cwd;
  ConfirmModal? _activeModal;
  final List<PanelOverlay> _panelStack = [];
  late final PanelController _panels;
  final DockManager _dockManager = DockManager();
  bool _renderedPanelLastFrame = false;
  final Set<String> _autoApprovedTools = {
    ...ToolPermissions.defaultTrustedTools,
  };
  final AgentManager? _manager;
  final LlmClientFactory? _llmFactory;
  GlueConfig? _config;
  final String? _systemPrompt;
  final CommandExecutor _executor;
  final ShellJobManager _jobManager;
  final SessionState? _sessionState;
  late final SlashAutocomplete _autocomplete;
  late final AtFileHint _atHint;
  late final ShellAutocomplete _shellComplete;
  late final SessionManager _sessionManager;
  bool _titleGenerated = false;
  bool _bashMode = false;
  Process? _bashRunProcess;
  DateTime? _lastCtrlC;

  final Map<String, _SubagentGroup> _subagentGroups = {};
  final List<_SubagentGroup?> _outputLineGroups = [];

  final bool _startupContinue;
  final String? _startupPrompt;
  final bool _printMode;
  final bool _jsonMode;
  final String? _resumeSessionId;
  final Observability? _obs;
  ObservabilitySpan? _turnSpan;
  final DebugController? _debugController;
  late final SkillRuntime _skillRuntime;
  PermissionMode _permissionMode;
  final Set<String> _earlyApprovedIds = {};

  App({
    required this.terminal,
    required this.layout,
    required this.editor,
    required this.agent,
    required String modelId,
    AgentManager? manager,
    LlmClientFactory? llmFactory,
    GlueConfig? config,
    String? systemPrompt,
    Set<String>? extraTrustedTools,
    SessionStore? sessionStore,
    SessionState? sessionState,
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
        _manager = manager,
        _llmFactory = llmFactory,
        _config = config,
        _systemPrompt = systemPrompt,
        _executor = executor ?? HostExecutor(const ShellConfig()),
        _jobManager = jobManager ??
            ShellJobManager(executor ?? HostExecutor(const ShellConfig())),
        _sessionState = sessionState,
        _startupContinue = startupContinue,
        _startupPrompt = startupPrompt,
        _printMode = printMode,
        _jsonMode = jsonMode,
        _resumeSessionId = resumeSessionId,
        _obs = obs,
        _debugController = debugController,
        _permissionMode = config?.permissionMode ?? PermissionMode.confirm {
    _cwd = _environment.cwd;
    _sessionManager = SessionManager(
      environment: _environment,
      sessionStore: sessionStore,
    );
    _panels = PanelController(panelStack: _panelStack, render: _render);
    _skillRuntime = skillRuntime ??
        SkillRuntime(
          cwd: _cwd,
          extraPathsProvider: () => _config?.skillPaths ?? const [],
          environment: _environment,
        );
    if (extraTrustedTools != null) {
      _autoApprovedTools.addAll(extraTrustedTools);
    }
    _initCommands();
    _autocomplete = SlashAutocomplete(_commands);
    _atHint = AtFileHint();
    _shellComplete = ShellAutocomplete(ShellCompleter());
    _syncToolFilter();
  }

  PermissionGate get _permissionGate => PermissionGate(
        permissionMode: _permissionMode,
        trustedTools: _autoApprovedTools,
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
      modelId: services.config.model,
      manager: services.manager,
      llmFactory: services.llmFactory,
      config: services.config,
      systemPrompt: services.systemPrompt,
      extraTrustedTools: services.trustedTools,
      sessionStore: services.sessionStore,
      sessionState: services.sessionState,
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

  /// Returns a JSON-serializable snapshot of internal state for DevTools.
  Map<String, dynamic> devtoolsState(String name) => switch (name) {
        'getAgentState' => {
            'mode': _mode.name,
            'tokenCount': agent.tokenCount,
            'model': _modelId,
            'conversationLength': agent.conversation.length,
            'pendingTools': _mode == AppMode.toolRunning ? 'active' : 'none',
          },
        'getConfig' => {
            'provider': _config?.provider.name ?? 'unknown',
            'model': _config?.model ?? 'unknown',
            'maxSubagentDepth': _config?.maxSubagentDepth ?? 0,
            'bashMaxLines': _config?.bashMaxLines ?? 0,
          },
        'getSessionInfo' => {
            'blockCount': _blocks.length,
            'scrollOffset': _scrollOffset,
            'dockerMounts': _sessionState?.dockerMounts.length ?? 0,
          },
        'getToolHistory' => {
            'note': 'Tool history tracking not yet implemented',
          },
        _ => {'error': 'Unknown extension: $name'},
      };

  /// Run the application event loop.
  ///
  /// Enters raw / alt-screen mode and processes events until the user
  /// requests an exit.
  Future<void> run() async {
    // Non-interactive print mode: stream response to stdout and exit.
    if (_printMode) {
      await _runPrintMode();
      return;
    }

    terminal.enableRawMode();
    terminal.enableAltScreen();
    terminal.enableMouse();
    terminal.clearScreen();
    layout.apply();

    _blocks.add(_ConversationEntry.system(
      '\x1b[33m◆\x1b[0m Glue v${AppConstants.version} — $_modelId\n'
      'Working directory: ${_shortenPath(_cwd)}\n'
      'Type /help for commands.',
    ));

    final termSub = terminal.events.listen(_handleTerminalEvent);
    final appSub = _events.stream.listen(_handleAppEvent);
    _subagentSub = _manager?.updates.listen(_handleSubagentUpdate);
    final jobSub = _jobManager.events.listen(_handleJobEvent);

    _render();

    if (_resumeSessionId != null) {
      final sessions = _sessionManager.listSessions();
      final match = sessions.where((s) => s.id == _resumeSessionId).toList();
      if (match.isNotEmpty) {
        final result = _resumeSession(match.first);
        if (result.isNotEmpty) {
          _blocks.add(_ConversationEntry.system(result));
        }
        _render();
      } else {
        _blocks.add(_ConversationEntry.system(
          'Session $_resumeSessionId not found.',
        ));
        _render();
      }
    } else if (_startupContinue) {
      final sessions = _sessionManager.listSessions();
      if (sessions.isNotEmpty) {
        final result = _resumeSession(sessions.first);
        if (result.isNotEmpty) {
          _blocks.add(_ConversationEntry.system(result));
        }
        _render();
      } else {
        _blocks.add(_ConversationEntry.system('No sessions to continue.'));
        _render();
      }
    } else if (_startupPrompt case final prompt? when prompt.isNotEmpty) {
      _events.add(UserSubmit(prompt));
    }

    try {
      await _exitCompleter.future;
    } finally {
      // Stop all event sources before touching terminal state.
      _stopSplashAnimation();
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
      await _agentSub?.cancel();
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
  Future<void> _runPrintMode() async {
    await _runPrintModeImpl(this);
  }

  /// Cleanly shut down the application.
  void shutdown() {
    requestExit();
  }

  // ── Slash commands ──────────────────────────────────────────────────────

  void _initCommands() {
    _commands = BuiltinCommands.create(
      openHelpPanel: _openHelpPanel,
      clearConversation: _clearConversation,
      requestExit: requestExit,
      openModelPanel: _openModelPanel,
      switchModelByQuery: _switchModelByQuery,
      sessionInfo: _buildSessionInfo,
      listTools: _buildToolsOutput,
      openHistoryPanel: _openHistoryPanel,
      openResumePanel: _openResumePanel,
      openDevTools: _openDevTools,
      toggleDebug: _toggleDebugMode,
      openSkillsPanel: _openSkillsPanel,
    );
  }

  String _clearConversation() {
    return _clearConversationImpl(this);
  }

  String _switchModelByQuery(String query) {
    return _switchModelByQueryImpl(this, query);
  }

  String _buildSessionInfo() {
    return _buildSessionInfoImpl(this);
  }

  String _buildToolsOutput() {
    return _buildToolsOutputImpl(this);
  }

  String _openDevTools() {
    return _openDevToolsImpl(this);
  }

  String _toggleDebugMode() {
    return _toggleDebugModeImpl(this);
  }

  void _addSystemMessage(String message) {
    _addSystemMessageImpl(this, message);
  }

  String _resumeSession(SessionMeta session) {
    return _resumeSessionImpl(this, session);
  }

  /// Fire-and-forget: generate a session title in the background.
  void _generateTitle(String userMessage) {
    _generateTitleImpl(this, userMessage);
  }

  LlmClient? _createTitleLlmClient() {
    return _createTitleLlmClientImpl(this);
  }

  _TitleTarget _resolveTitleTarget(GlueConfig config) {
    return _resolveTitleTargetImpl(config);
  }

  static String _timeAgo(DateTime time) {
    return _timeAgoImpl(time);
  }

  void _ensureSessionStore() {
    _ensureSessionStoreImpl(this);
  }

  void _appendSessionReplayEntries(List<SessionReplayEntry> entries) {
    _appendSessionReplayEntriesImpl(this, entries);
  }

  SkillRegistry _discoverSkills() {
    return _skillRuntime.refresh();
  }

  void _openHelpPanel() {
    _panels.openHelp(commands: _commands.commands);
  }

  void _openResumePanel() {
    _panels.openResume(
      sessions: _sessionManager.listSessions(),
      timeAgo: _timeAgo,
      shortenPath: _shortenPath,
      onResume: _resumeSession,
      addSystemMessage: _addSystemMessage,
    );
  }

  void _openHistoryPanel() {
    final entries = <HistoryPanelEntry>[];
    var userIndex = 0;
    for (final block in _blocks) {
      if (block.kind == _EntryKind.user) {
        entries.add(HistoryPanelEntry(
          userMessageIndex: userIndex,
          text: block.text,
        ));
        userIndex++;
      }
    }

    _panels.openHistory(
      entries: entries,
      onFork: _forkSession,
      addSystemMessage: _addSystemMessage,
    );
  }

  void _forkSession(int userMessageIndex, String messageText) {
    _forkSessionImpl(this, userMessageIndex, messageText);
  }

  void _openModelPanel() {
    final config = _config;
    if (config == null) return;

    unawaited(_panels.openModel(
      config: config,
      cacheDir: _environment.cacheDir,
      currentModelId: _modelId,
      onModelSelected: _switchToModelEntry,
      addSystemMessage: _addSystemMessage,
      isSelectionEnabled: () => true,
    ));
  }

  void _openSkillsPanel() {
    final registry = _discoverSkills();
    if (registry.isEmpty) {
      _addSystemMessage('No skills found.\n\n'
          'To add skills, create directories with SKILL.md files in:\n'
          '  ~/.glue/skills/<skill-name>/SKILL.md (global)\n'
          '  .glue/skills/<skill-name>/SKILL.md (project-local)');
      _render();
      return;
    }

    var panel = _findSkillsDockedPanel();
    if (panel == null) {
      panel = SkillsDockedPanel(skills: registry.list());
      _dockManager.add(panel);
    } else {
      panel.updateSkills(registry.list());
    }

    if (panel.visible) {
      panel.dismiss();
      _render();
      return;
    }

    panel.show();
    unawaited(panel.selection.then((skillName) async {
      if (skillName != null) {
        await _activateSkillFromUi(skillName);
      }
      _render();
    }));
    _render();
  }

  SkillsDockedPanel? _findSkillsDockedPanel() {
    for (final panel in _dockManager.panels) {
      if (panel is SkillsDockedPanel) return panel;
    }
    return null;
  }

  Future<void> _activateSkillFromUi(String skillName) async {
    await _activateSkillFromUiImpl(this, skillName);
  }

  String _switchToModelEntry(ModelEntry entry) {
    return _switchToModelEntryImpl(this, entry);
  }

  // ── Terminal event handling ─────────────────────────────────────────────

  void _handleTerminalEvent(TerminalEvent event) {
    _handleTerminalEventImpl(this, event);
  }

  // ── App event handling ──────────────────────────────────────────────────

  void _handleAppEvent(AppEvent event) {
    _handleAppEventImpl(this, event);
  }

  // ── Agent interaction ──────────────────────────────────────────────────

  void _endTurnSpan({Map<String, dynamic>? extra}) {
    _endTurnSpanImpl(this, extra: extra);
  }

  void _startAgent(String displayMessage, {String? expandedMessage}) {
    _startAgentImpl(this, displayMessage, expandedMessage: expandedMessage);
  }

  void _handleAgentEvent(AgentEvent event) {
    _handleAgentEventImpl(this, event);
  }

  Future<void> _executeAndCompleteTool(ToolCall call) async {
    await _executeAndCompleteToolImpl(this, call);
  }

  void _cancelAgent() {
    _cancelAgentImpl(this);
  }

  // ── Permission mode ──────────────────────────────────────────────────

  void _syncToolFilter() {
    _syncToolFilterImpl(this);
  }

  void _persistTrustedTool(String name) {
    _persistTrustedToolImpl(this, name);
  }

  void _approveTool(ToolCall call) {
    _approveToolImpl(this, call);
  }

  void _denyTool(ToolCall call) {
    _denyToolImpl(this, call);
  }

  void _showToolConfirmModal(ToolCall call) {
    _showToolConfirmModalImpl(this, call);
  }

  // ── Bash mode ─────────────────────────────────────────────────────────

  void _handleBashSubmit(String text) {
    _handleBashSubmitImpl(this, text);
  }

  Future<void> _runBlockingBash(String command) async {
    await _runBlockingBashImpl(this, command);
  }

  void _cancelBash() {
    _cancelBashImpl(this);
  }

  void _startBackgroundJob(String command) {
    _startBackgroundJobImpl(this, command);
  }

  void _handleJobEvent(JobEvent event) {
    _handleJobEventImpl(this, event);
  }

  // ── Subagent updates ──────────────────────────────────────────────────

  void _handleSubagentUpdate(SubagentUpdate update) {
    _handleSubagentUpdateImpl(this, update);
  }

  // ── Rendering ──────────────────────────────────────────────────────────

  DateTime _lastRender = DateTime(0);
  bool _renderScheduled = false;
  static const _minRenderInterval = Duration(milliseconds: 16); // ~60fps

  // Splash liquid simulation state.
  LiquidSim? _liquidSim;
  Timer? _splashTimer;
  int _splashOriginCol = 0; // screen col of mascot left edge
  int _splashOriginRow = 0; // screen row of mascot top edge
  GooExplosion? _gooExplosion;

  void _startSplashAnimation() {
    _startSplashAnimationImpl(this);
  }

  void _stopSplashAnimation() {
    _stopSplashAnimationImpl(this);
  }

  void _triggerExplosion() {
    _triggerExplosionImpl(this);
  }

  void _handleSplashClick(int screenX, int screenY) {
    _handleSplashClickImpl(this, screenX, screenY);
  }

  void _startSpinner() {
    _startSpinnerImpl(this);
  }

  void _stopSpinner() {
    _stopSpinnerImpl(this);
  }

  void _render() {
    _renderImpl(this);
  }

  void _doRender() {
    _doRenderImpl(this);
  }
}
