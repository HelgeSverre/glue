import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/terminal/layout.dart';
import 'package:glue/src/input/line_editor.dart' show InputAction;
import 'package:glue/src/input/text_area_editor.dart';
import 'package:glue/src/input/streaming_input_handler.dart';
import 'package:glue/src/input/file_expander.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:glue/src/commands/builtin_commands.dart';
import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/conversation/entry.dart';
import 'package:glue/src/extensions/time_ago.dart';
import 'package:glue/src/extensions/token_format.dart';
import 'package:glue/src/services/approval_state.dart';
import 'package:glue/src/services/conversation_view.dart';
import 'package:glue/src/services/lifecycle.dart';
import 'package:glue/src/app/model_display.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:glue/src/ui/model_panel_formatter.dart'
    show CatalogRow, ModelAvailability;
import 'package:glue/src/rendering/block_renderer.dart';
import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/ui/modal.dart';
import 'package:glue/src/ui/dock_manager.dart';
import 'package:glue/src/ui/panel_modal.dart';
import 'package:glue/src/ui/modal_surface.dart';
import 'package:glue/src/ui/at_file_hint.dart';
import 'package:glue/src/ui/autocomplete_overlay.dart';
import 'package:glue/src/ui/shell_autocomplete.dart';
import 'package:glue/src/ui/slash_autocomplete.dart';

// ---------------------------------------------------------------------------
// Application events
// ---------------------------------------------------------------------------

/// Events that flow through the application event bus.
sealed class AppEvent {}

class UserSubmit extends AppEvent {
  final String text;
  UserSubmit(this.text);
}

class UserCancel extends AppEvent {}

class UserScroll extends AppEvent {
  final int delta;
  UserScroll(this.delta);
}

class UserResize extends AppEvent {
  final int cols;
  final int rows;
  UserResize(this.cols, this.rows);
}

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

enum _ToolPhase {
  preparing,
  awaitingApproval,
  running,
  done,
  denied,
  cancelled,
  error,
}

class _ToolCallUiState {
  final ToolCallId id;
  final String name;
  Map<String, dynamic>? args;
  _ToolPhase phase;
  _ToolCallUiState(
      {required this.id,
      required this.name,
      this.phase = _ToolPhase.preparing});

  ToolCallRenderState toRenderState() => ToolCallRenderState(
        name: name,
        args: args,
        phase: switch (phase) {
          _ToolPhase.preparing => ToolCallPhase.preparing,
          _ToolPhase.awaitingApproval => ToolCallPhase.awaitingApproval,
          _ToolPhase.running => ToolCallPhase.running,
          _ToolPhase.done => ToolCallPhase.done,
          _ToolPhase.denied => ToolCallPhase.denied,
          _ToolPhase.cancelled => ToolCallPhase.cancelled,
          _ToolPhase.error => ToolCallPhase.error,
        },
      );
}

class _TitleTarget {
  final ModelRef ref;

  const _TitleTarget({required this.ref});
}

_TitleTarget _resolveTitleTarget(GlueConfig config) {
  return _TitleTarget(ref: config.smallModel ?? config.activeModel);
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

  static const _minRenderInterval = Duration(milliseconds: 16); // ~60fps

  final Terminal terminal;
  final Layout layout;
  final TextAreaEditor editor;
  final AgentCore agent;
  final _events = StreamController<AppEvent>.broadcast();

  AppMode _mode = AppMode.idle;
  final List<ConversationEntry> _blocks = [];
  final Map<ToolCallId, _ToolCallUiState> _toolUi = {};
  int _scrollOffset = 0;

  int _spinnerFrame = 0;
  Timer? _spinnerTimer;
  String _streamingText = '';
  String _streamingThinking = '';
  StreamSubscription<AgentEvent>? _agentSub;
  StreamSubscription<SubagentUpdate>? _subagentSub;
  final _exitCompleter = Completer<void>();

  late final SlashCommandRegistry _commands;
  String _modelId;
  final Environment _environment;
  late final String _cwd;
  ConfirmModal? _activeModal;
  final List<PanelOverlay> _panelStack = [];
  late final ModalSurface _panels;
  final DockManager _dockManager = DockManager();
  bool _renderedPanelLastFrame = false;
  final Set<String> _autoApprovedTools = {
    ...ToolPermissions.defaultTrustedTools,
  };
  final AgentManager? _manager;
  final McpClientPool _mcpPool;
  final LlmClientFactory? _llmFactory;
  GlueConfig? _config;
  final String? _systemPrompt;
  final CommandExecutor _executor;
  final ShellJobManager _jobManager;
  late final SlashAutocomplete _autocomplete;
  late final AtFileHint _atHint;
  late final ShellAutocomplete _shellComplete;
  late final SessionManager _sessionManager;
  late final ConversationView _conversation;
  late final ApprovalState _approvalState;
  late final Lifecycle _lifecycle;
  late final SlashCommandContext _slashContext;
  bool _bashMode = false;
  Process? _bashRunProcess;
  ObservabilitySpan? _bashSpan;
  DateTime? _lastCtrlC;

  final Map<String, SubagentGroup> _subagentGroups = {};
  final List<SubagentGroup?> _outputLineGroups = [];

  final bool _startupContinue;
  final String? _startupPrompt;
  final bool _printMode;
  final bool _jsonMode;
  final String? _resumeSessionId;
  final Observability? _obs;
  ObservabilitySpan? _turnSpan;
  final DebugController? _debugController;
  late final SkillRuntime _skillRuntime;
  ApprovalMode _approvalMode;
  final Set<ToolCallId> _earlyApprovedIds = {};

  DateTime _lastRender = DateTime(0);
  bool _renderScheduled = false;

  App({
    required this.terminal,
    required this.layout,
    required this.editor,
    required this.agent,
    required String modelId,
    AgentManager? manager,
    McpClientPool? mcpPool,
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
        _manager = manager,
        _mcpPool = mcpPool ??
            McpClientPool(
              config: const McpConfig(),
              credentials: config?.credentials ??
                  CredentialStore(path: '/dev/null', env: const {}),
            ),
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
    _manager?.onPersistEvent = (type, data) {
      _sessionManager.logEvent(type, data);
    };
    _manager?.onSubagentUsage = (stats) {
      _sessionManager.recordUsage(stats, role: 'subagent');
    };
    _panels = ModalSurface(
      panelStack: _panelStack,
      render: _render,
    );
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
  }

  PermissionGate get _permissionGate => PermissionGate(
        approvalMode: _approvalMode,
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

    // Surface objects (terminal/layout/editor) are constructed here, not
    // by the harness. ServiceLocator deliberately does not bundle them so
    // that core/ can stay below surface/ in the layered architecture.
    final terminal = Terminal();
    final layout = Layout(terminal);
    final editor = TextAreaEditor();

    return App(
      terminal: terminal,
      layout: layout,
      editor: editor,
      agent: services.agent,
      modelId: services.config.activeModel.modelId,
      manager: services.manager,
      mcpPool: services.mcpPool,
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

  /// Request a clean exit. Can be called from signal handlers.
  void requestExit() {
    _activeModal?.cancel();
    if (!_exitCompleter.isCompleted) _exitCompleter.complete();
  }

  /// Run the application event loop.
  Future<void> run() async {
    if (_printMode) {
      await _runPrintMode();
      return;
    }

    terminal.enableRawMode();
    terminal.enableAltScreen();
    terminal.enableMouse();
    terminal.clearScreen();
    layout.apply();

    _blocks.add(ConversationEntry.system(
      '\x1b[33m◆\x1b[0m Glue v${AppConstants.version} — $_modelId\n'
      'Working directory: ${_environment.shortenPath(_cwd)}\n'
      'Type /help for commands.',
    ));

    final termSub = terminal.events.listen(_handleTerminalEvent);
    final appSub = _events.stream.listen(_handleAppEvent);
    _subagentSub = _manager?.updates.listen(_handleSubagentUpdate);
    final jobSub = _jobManager.events.listen(_handleJobEvent);

    _render();

    if (_resumeSessionId != null) {
      final sessions = _sessionManager.listSessions();
      if (_resumeSessionId.isEmpty) {
        _commands.execute('/resume');
        _render();
      } else {
        final match =
            sessions.where((s) => s.id.value == _resumeSessionId).toList();
        if (match.isNotEmpty) {
          final result = _resumeSession(match.first);
          if (result.isNotEmpty) {
            _blocks.add(ConversationEntry.system(result));
          }
          _render();
        } else {
          _blocks.add(ConversationEntry.system(
            'Session $_resumeSessionId not found.',
          ));
          _render();
        }
      }
    } else if (_startupContinue) {
      final sessions = _sessionManager.listSessions();
      if (sessions.isNotEmpty) {
        final result = _resumeSession(sessions.first);
        if (result.isNotEmpty) {
          _blocks.add(ConversationEntry.system(result));
        }
        _render();
      } else {
        _blocks.add(ConversationEntry.system('No sessions to continue.'));
        _render();
      }
    }

    if (_startupPrompt case final prompt? when prompt.isNotEmpty) {
      _events.add(UserSubmit(prompt));
    }

    try {
      await _exitCompleter.future;
    } finally {
      _stopSpinner();
      for (final tool in agent.tools.values) {
        try {
          await tool.dispose();
        } catch (_) {}
      }
      await _sessionManager.closeCurrent();
      await _obs?.flush();
      await _obs?.close();
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

  /// Cleanly shut down the application.
  void shutdown() {
    requestExit();
  }

  // ── Slash commands ──────────────────────────────────────────────────────

  void _initCommands() {
    _conversation = ConversationView(
      blocks: _blocks,
      subagentGroups: _subagentGroups,
      streamingTextGetter: () => _streamingText,
      render: _render,
      resetStreamingText: () {
        _streamingText = '';
        _streamingThinking = '';
      },
      clearScreen: terminal.clearScreen,
      resetScrollOffset: () => _scrollOffset = 0,
      clearToolUi: _toolUi.clear,
      clearSubagentGroups: () {
        _subagentGroups.clear();
        _outputLineGroups.clear();
      },
    );
    _approvalState = ApprovalState(
      get: () => _approvalMode,
      set: (m) => _approvalMode = m,
    );
    _lifecycle = Lifecycle(onExit: requestExit);

    late final SlashCommandRegistry registry;
    _slashContext = SlashCommandContext(
      configGetter: () => _config,
      llmFactoryGetter: () => _llmFactory,
      agentGetter: () => agent,
      cwdGetter: () => _cwd,
      modelIdGetter: () => _modelId,
      isIdleGetter: () => _mode == AppMode.idle,
      environment: _environment,
      session: _sessionManager,
      skills: _skillRuntime,
      debug: _debugController,
      dockManager: _dockManager,
      editor: editor,
      mcpPool: _mcpPool,
      autoApprovedTools: _autoApprovedTools,
      ensureSession: _ensureSessionStore,
      backfillTitle: _generateTitle,
      switchModel: _switchToModelRow,
      conversation: _conversation,
      approval: _approvalState,
      lifecycle: _lifecycle,
      panels: _panels,
      commandsGetter: () => registry.commands,
    );

    registry = BuiltinCommands.create(_slashContext);
    _commands = registry;
  }

  // ── Model switching ────────────────────────────────────────────────────

  /// Apply a model switch from a [CatalogRow]. Handles the Ollama
  /// pull-confirm flow when an unpulled tag is selected, then mutates
  /// `agent.llm`, `_config`, `_modelId`, and persists the active model on
  /// the session store.
  ///
  /// Returns an inline message for synchronous switches; returns `''` when
  /// an async confirm is pending (the pull flow posts the result via
  /// `_addSystemMessage`).
  String _switchToModelRow(CatalogRow row) {
    if (row.providerId == 'ollama' &&
        row.availability != ModelAvailability.installed &&
        row.availability != ModelAvailability.installedOnly) {
      final config = _config;
      if (config != null) {
        final provider = config.catalogData.providers['ollama'];
        if (provider != null) {
          final discovery = OllamaDiscovery(
            baseUrl: Uri.parse(provider.baseUrl ?? 'http://localhost:11434'),
          );
          _confirmAndPullOllamaModel(
            tag: row.model.id,
            discovery: discovery,
            onPull: () {
              final message = _applyModelSwitch(row);
              _addSystemMessage(message);
              _render();
            },
          );
          return '';
        }
      }
    }
    return _applyModelSwitch(row);
  }

  String _applyModelSwitch(CatalogRow row) {
    final factory = _llmFactory;
    final config = _config;
    final prompt = _systemPrompt;
    final ref = ModelRef(providerId: row.providerId, modelId: row.model.id);
    if (factory != null && config != null && prompt != null) {
      final llm = factory.createFor(ref, systemPrompt: prompt);
      agent.llm = llm;
      _config = config.copyWith(activeModel: ref);
    }
    _modelId = ref.modelId;
    _sessionManager.updateSessionModel(modelRef: ref.toString());
    return 'Switched to ${row.model.name}';
  }

  /// Kick off the "pull this model?" confirmation flow for an Ollama tag.
  ///
  /// Flow:
  ///   1. Ask Ollama which tags are already installed (cached; fail-soft).
  ///   2. If [tag] is already present, invoke [onPull] directly — no modal.
  ///   3. Otherwise show a [ConfirmModal]; on **Yes** stream `POST /api/pull`
  ///      and post progress as system messages, then invoke [onPull].
  ///   4. On **No** post a single "aborted" system message and leave state
  ///      unchanged.
  ///
  /// Discovery failures (daemon down) skip the modal and proceed — we can't
  /// confirm the model is missing, and false-positive prompts are worse
  /// than an eventual 404 from the inference call.
  void _confirmAndPullOllamaModel({
    required String tag,
    required OllamaDiscovery discovery,
    required void Function() onPull,
  }) {
    () async {
      final installed = await discovery.listInstalled();
      final isPresent = installed.any((m) => m.tag == tag);
      if (installed.isEmpty || isPresent) {
        onPull();
        return;
      }

      _mode = AppMode.confirming;
      _activeModal = ConfirmModal(
        title: "Pull '$tag' from Ollama?",
        bodyLines: const [
          'Model is not installed locally.',
          'This downloads several GB and may take a while.',
        ],
        choices: const [
          ModalChoice('Yes', 'y'),
          ModalChoice('No', 'n'),
        ],
      );
      _render();

      final idx = await _activeModal!.result;
      _activeModal = null;
      _mode = AppMode.idle;

      if (idx != 0) {
        _addSystemMessage('Pull aborted — model not switched.');
        _render();
        return;
      }

      _addSystemMessage("Pulling '$tag' from Ollama…");
      _render();

      discovery.invalidateCache();

      String? lastStatus;
      OllamaPullProgress? finalFrame;
      try {
        await for (final frame in discovery.pullModel(tag)) {
          finalFrame = frame;
          if (frame.hasError) break;
          if (frame.status != lastStatus) {
            lastStatus = frame.status;
            _addSystemMessage('  ${frame.status}');
            _render();
          }
        }
      } catch (e) {
        _addSystemMessage('Pull failed: $e');
        _render();
        return;
      }

      if (finalFrame == null || finalFrame.hasError) {
        final err = finalFrame?.error ?? 'unknown error';
        _addSystemMessage('Pull failed: $err');
        _render();
        return;
      }

      if (!finalFrame.isSuccess) {
        _addSystemMessage(
          'Pull ended without success (last status: ${finalFrame.status}).',
        );
        _render();
        return;
      }

      discovery.invalidateCache();
      onPull();
    }();
  }

  // ── Rendering ──────────────────────────────────────────────────────────

  void _render() {
    final now = DateTime.now();
    if (now.difference(_lastRender) < _minRenderInterval) {
      if (!_renderScheduled) {
        _renderScheduled = true;
        Future.delayed(_minRenderInterval, () {
          _renderScheduled = false;
          if (DateTime.now().difference(_lastRender) >= _minRenderInterval) {
            _doRender();
          }
        });
      }
      return;
    }
    _doRender();
  }

  void _doRender() {
    _lastRender = DateTime.now();

    final panelActive = _panelStack.isNotEmpty;
    if (_renderedPanelLastFrame && !panelActive) {
      terminal.resetScrollRegion();
      terminal.clearScreen();
      layout.apply();
    }

    if (_blocks.length > AppConstants.maxConversationBlocks) {
      _blocks.removeRange(
          0, _blocks.length - AppConstants.maxConversationBlocks);
    }
    final dockInsets = _dockManager.resolveInsets(
      terminalColumns: terminal.columns,
      terminalRows: terminal.rows,
    );
    layout.applyDockGutters(
      left: dockInsets.left,
      top: dockInsets.top,
      right: dockInsets.right,
      bottom: dockInsets.bottom,
    );

    terminal.hideCursor();
    final renderer = BlockRenderer(layout.outputWidth);

    // 1. Build all output lines from blocks.
    final outputLines = <String>[];
    _outputLineGroups.clear();
    for (final block in _blocks) {
      final text = switch (block.kind) {
        EntryKind.user => renderer.renderUser(block.text),
        EntryKind.assistant => renderer.renderAssistant(block.text),
        EntryKind.thinking => renderer.renderThinking(block.text),
        EntryKind.toolCall => renderer.renderToolCall(block.text, block.args),
        EntryKind.toolCallRef => renderer.renderToolCallRef(
            _toolUi[ToolCallId(block.text)]?.toRenderState(),
          ),
        EntryKind.toolResult => renderer.renderToolResult(block.text),
        EntryKind.error => renderer.renderError(block.text),
        EntryKind.subagent => renderer.renderSubagent(block.text),
        EntryKind.subagentGroup => renderer.renderSubagent(block.group!.expanded
            ? '${block.group!.summary}\n${block.group!.entries.map((e) => e.render(expanded: true)).join('\n')}'
            : block.group!.summary),
        EntryKind.system => renderer.renderSystem(block.text),
        EntryKind.bash => renderer.renderBash(
            block.expandedText ?? 'shell',
            block.text,
            maxLines: _config?.bashMaxLines ?? 50,
          ),
      };
      final lines = text.split('\n');
      final group = block.kind == EntryKind.subagentGroup ? block.group : null;
      for (var j = 0; j < lines.length; j++) {
        _outputLineGroups.add(group);
      }
      _outputLineGroups.add(null);
      outputLines.addAll(lines);
      outputLines.add('');
    }

    // If streaming reasoning, render it above the (still-empty) assistant
    // text — when both buffers are non-empty (Anthropic interleaves them in
    // edge cases) the user sees thinking "above" the conclusion.
    if (_streamingThinking.isNotEmpty) {
      outputLines
          .addAll(renderer.renderThinking(_streamingThinking).split('\n'));
    }

    if (_streamingText.isNotEmpty) {
      outputLines.addAll(renderer.renderAssistant(_streamingText).split('\n'));
    }

    if (_activeModal != null && !_activeModal!.isComplete) {
      outputLines.add('');
      outputLines.addAll(_activeModal!.render(layout.outputWidth));
    }

    outputLines.add('');

    if (panelActive) {
      _renderedPanelLastFrame = true;
      var grid = outputLines;
      for (final panel in _panelStack) {
        grid = panel.render(terminal.columns, terminal.rows, grid);
      }
      terminal.hideCursor();
      for (var i = 0; i < grid.length && i < terminal.rows; i++) {
        terminal.moveTo(i + 1, 1);
        terminal.clearLine();
        terminal.write(grid[i]);
      }
      return;
    }

    _renderedPanelLastFrame = false;

    // 2. Reserve overlay space for autocomplete (before computing viewport).
    final overlayHeight = _shellComplete.active
        ? _shellComplete.overlayHeight
        : _autocomplete.active
            ? _autocomplete.overlayHeight
            : _atHint.overlayHeight;
    layout.setOverlayHeight(overlayHeight);

    // 3. Compute visible window.
    final viewportHeight = layout.outputBottom - layout.outputTop + 1;
    final totalLines = outputLines.length;
    final maxScroll = (totalLines - viewportHeight).clamp(0, totalLines);
    _scrollOffset = _scrollOffset.clamp(0, maxScroll);

    final firstLine =
        (totalLines - viewportHeight - _scrollOffset).clamp(0, totalLines);
    final endLine = (firstLine + viewportHeight).clamp(0, totalLines);
    final visibleLines = firstLine < endLine
        ? outputLines.sublist(firstLine, endLine)
        : <String>[];

    layout.paintOutputViewport(visibleLines);

    // 3b. Render docked panels over output after content paint.
    final dockPlans = _dockManager.buildRenderPlans(
      viewport: DockViewport(
        outputTop: layout.outputTop,
        outputBottom: layout.outputBottom,
        outputLeft: layout.outputLeft,
        outputRight: layout.outputRight,
        overlayTop: layout.overlayTop,
      ),
      terminalColumns: terminal.columns,
    );
    for (final plan in dockPlans) {
      layout.paintRect(
        row: plan.rect.row,
        col: plan.rect.col,
        width: plan.rect.width,
        height: plan.rect.height,
        lines: plan.lines,
      );
    }

    // 4. Autocomplete / @file / shell overlay.
    if (_shellComplete.active) {
      layout.paintOverlay(_shellComplete.render(layout.outputWidth));
    } else if (_autocomplete.active) {
      layout.paintOverlay(_autocomplete.render(layout.outputWidth));
    } else if (_atHint.active) {
      layout.paintOverlay(_atHint.render(layout.outputWidth));
    } else {
      layout.paintOverlay([]);
    }

    // 5. Status bar.
    final modeIndicator = switch (_mode) {
      AppMode.idle => 'Ready',
      AppMode.streaming => '${_spinnerFrames[_spinnerFrame]} Generating',
      AppMode.toolRunning => '⚙ Tool',
      AppMode.confirming => '? Approve',
      AppMode.bashRunning => '! Running',
    };
    final shortCwd = _environment.shortenPath(_cwd);
    final modeLabel = '[${_approvalMode.label}]';
    final statusLeft = ' \x1b[1m$modeIndicator\x1b[22m ';

    const sep = ' · ';
    final scrollSeg = _scrollOffset > 0 ? '↑$_scrollOffset' : null;
    final rightSegs = [
      formatStatusModelLabel(
          _config?.activeModel, _config?.catalogData, _modelId),
      modeLabel,
      ansiTruncate(shortCwd, 30),
      if (scrollSeg != null) scrollSeg,
      '${formatCompactTokens(agent.stats.totalTokens)} tokens',
    ];
    final statusRight = ' ${rightSegs.join(sep)} ';
    layout.paintStatus(statusLeft, statusRight);

    // 6. Input area — MUST be last so cursor lands here.
    final prompt = switch ((_mode, _bashMode)) {
      (AppMode.idle, true) => '! ',
      (AppMode.idle, false) => '❯ ',
      _ => '  ',
    };
    final promptStyle = switch ((_mode, _bashMode)) {
      (AppMode.idle, true) => AnsiStyle.red,
      (AppMode.idle, false) => AnsiStyle.yellow,
      _ => AnsiStyle.dim,
    };
    final showCursor = !(_mode == AppMode.confirming && _activeModal != null);
    layout.paintInput(
      prompt,
      editor.lines,
      editor.cursorRow,
      editor.cursorCol,
      showCursor: showCursor,
      promptStyle: promptStyle,
    );
  }

  // ── Event routing ──────────────────────────────────────────────────────

  void _handleAppEvent(AppEvent event) {
    switch (event) {
      case UserSubmit(:final text):
        if (_bashMode) {
          _handleBashSubmit(text);
        } else if (text.startsWith('/')) {
          final result = _commands.execute(text);
          if (result != null && result.isNotEmpty) {
            _blocks.add(ConversationEntry.system(result));
          }
          _render();
        } else {
          final expanded = expandFileRefs(text);
          _ensureSessionStore();
          _sessionManager.logEvent('user_message', {'text': expanded});
          if (!_sessionManager.titleInitialRequested &&
              !_sessionManager.titleManuallyOverridden) {
            _sessionManager.titleInitialRequested = true;
            _generateTitle(expanded);
          }
          _startAgent(
            text,
            expandedMessage: expanded != text ? expanded : null,
          );
        }

      case UserCancel():
        _cancelAgent();

      case UserScroll(:final delta):
        _scrollOffset = (_scrollOffset + delta).clamp(0, 999999);
        _render();

      case UserResize():
        layout.apply();
        terminal.clearScreen();
        // Preserve the user's scroll position across resize. The render
        // pipeline clamps out-of-range offsets, so we don't need to recompute
        // here — worst case the user drifts by a few lines because wrapping
        // changed, which is much less jarring than snapping back to the tail.
        _render();
    }
  }

  void _handleTerminalEvent(TerminalEvent event) {
    switch (event) {
      case CharEvent() || KeyEvent():
        // Panel modal gets first crack at input.
        if (_panelStack.isNotEmpty && !_panelStack.last.isComplete) {
          if (_panelStack.last.handleEvent(event)) {
            _doRender();
            return;
          }
        }

        // Confirm modal gets next crack at input.
        if (_activeModal != null && !_activeModal!.isComplete) {
          if (_activeModal!.handleEvent(event)) {
            _render();
            return;
          }
        }

        // Focused docked panel handles input before editor/autocomplete.
        if (_dockManager.handleEvent(event)) {
          _render();
          return;
        }

        // Approval mode toggle — works in all modes.
        if (event case KeyEvent(key: Key.shiftTab)) {
          _approvalMode = _approvalMode.toggle;
          _render();
          return;
        }

        // Scroll handling — works in all modes.
        if (event case KeyEvent(key: Key.pageUp)) {
          final viewportHeight = layout.outputBottom - layout.outputTop + 1;
          _events.add(UserScroll(viewportHeight ~/ 2));
          return;
        }
        if (event case KeyEvent(key: Key.pageDown)) {
          final viewportHeight = layout.outputBottom - layout.outputTop + 1;
          _events.add(UserScroll(-(viewportHeight ~/ 2)));
          return;
        }
        // Ctrl+End jumps to the bottom and resumes follow-tail. Plain End is
        // reserved for the line editor (jump cursor to end of line).
        if (event case KeyEvent(key: Key.end, ctrl: true)) {
          _scrollOffset = 0;
          _render();
          return;
        }

        // Bash mode switching — before passing to editor.
        if (_mode == AppMode.idle) {
          if (!_bashMode &&
              event is CharEvent &&
              event.char == '!' &&
              editor.cursor == 0) {
            _bashMode = true;
            _render();
            return;
          }
          if (_bashMode &&
              event is KeyEvent &&
              event.key == Key.backspace &&
              editor.cursor == 0) {
            _bashMode = false;
            _shellComplete.dismiss();
            _render();
            return;
          }
        }

        if (_mode == AppMode.streaming ||
            _mode == AppMode.toolRunning ||
            _mode == AppMode.bashRunning) {
          final result = handleStreamingInput(
            event: event,
            isBashRunning: _mode == AppMode.bashRunning,
            editor: editor,
            autocomplete: _autocomplete,
            commands: _commands,
          );
          if (result.commandOutput != null &&
              result.commandOutput!.isNotEmpty) {
            _blocks.add(ConversationEntry.system(result.commandOutput!));
          }
          switch (result.action) {
            case StreamingAction.render:
              _render();
            case StreamingAction.swallowed:
              break;
            case StreamingAction.cancelAgent:
              _cancelAgent();
            case StreamingAction.cancelBash:
              _cancelBash();
          }
          return;
        }

        // Any active autocomplete overlay intercepts Up/Down/Tab/Enter/Esc.
        AutocompleteOverlay? activeOverlay;
        for (final o in <AutocompleteOverlay>[
          _autocomplete,
          _shellComplete,
          _atHint,
        ]) {
          if (o.active) {
            activeOverlay = o;
            break;
          }
        }

        if (activeOverlay != null) {
          if (event case KeyEvent(key: Key.up)) {
            activeOverlay.moveUp();
            _render();
            return;
          }
          if (event case KeyEvent(key: Key.down)) {
            activeOverlay.moveDown();
            _render();
            return;
          }
          if (event case KeyEvent(key: Key.escape)) {
            activeOverlay.dismiss();
            _render();
            return;
          }
          if (event case KeyEvent(key: Key.tab) || KeyEvent(key: Key.enter)) {
            // Slash-autocomplete: Enter on an exact match submits instead
            // of re-accepting the same text — fall through to submit below.
            final isEnter = event.key == Key.enter;
            final isEnterOnExactMatch = isEnter &&
                identical(activeOverlay, _autocomplete) &&
                _autocomplete.selectedText == editor.text;
            if (isEnterOnExactMatch) {
              _autocomplete.dismiss();
            } else {
              final result = activeOverlay.accept(editor.text, editor.cursor);
              if (result != null) {
                editor.setText(result.text, cursor: result.cursor);
              }
              _render();
              return;
            }
          }
        }

        // Normal idle mode — full input handling.
        final action = editor.handle(event);
        switch (action) {
          case InputAction.submit:
            _autocomplete.dismiss();
            _atHint.dismiss();
            _shellComplete.dismiss();
            final text = editor.lastSubmitted;
            if (text.isNotEmpty) {
              _events.add(UserSubmit(text));
            }
          case InputAction.interrupt:
            final now = DateTime.now();
            if (_lastCtrlC != null &&
                now.difference(_lastCtrlC!) <
                    AppConstants.ctrlCDoubleTapWindow) {
              _lastCtrlC = null;
              requestExit();
            } else {
              _lastCtrlC = now;
              _blocks
                  .add(ConversationEntry.system('Press Ctrl+C again to exit.'));
              _render();
            }
          case InputAction.changed:
            if (_bashMode) {
              _shellComplete.dismiss();
            } else {
              _autocomplete.update(editor.text, editor.cursor);
              if (!_autocomplete.active) {
                _atHint.update(editor.text, editor.cursor);
              } else {
                _atHint.dismiss();
              }
            }
            _render();
          case InputAction.requestCompletion:
            if (_bashMode) {
              _shellComplete
                  .requestCompletions(editor.text, editor.cursor)
                  .then((_) => _render());
            }
          default:
            break;
        }

      case ResizeEvent(:final cols, :final rows):
        _events.add(UserResize(cols, rows));

      case MouseEvent(
          :final y,
          :final isScroll,
          :final isScrollUp,
          :final isDown
        ):
        if (isScroll) {
          _events.add(UserScroll(isScrollUp ? 3 : -3));
        } else if (isDown) {
          if (y >= layout.outputTop && y <= layout.outputBottom) {
            final viewportHeight = layout.outputBottom - layout.outputTop + 1;
            final totalLines = _outputLineGroups.length;
            final firstLine = (totalLines - viewportHeight - _scrollOffset)
                .clamp(0, totalLines);
            final outputLineIdx = firstLine + (y - layout.outputTop);
            if (outputLineIdx >= 0 &&
                outputLineIdx < _outputLineGroups.length) {
              final group = _outputLineGroups[outputLineIdx];
              if (group != null) {
                group.expanded = !group.expanded;
                _render();
                return;
              }
            }
          }
        }

      case PasteEvent():
        // Dismiss popups before inserting paste content.
        _autocomplete.dismiss();
        _atHint.dismiss();
        final action = editor.handle(event);
        if (action == InputAction.changed) {
          _autocomplete.update(editor.text, editor.cursor);
          if (!_autocomplete.active) {
            _atHint.update(editor.text, editor.cursor);
          }
          _render();
        }
    }
  }

  // ── Agent orchestration ────────────────────────────────────────────────

  void _endTurnSpan({Map<String, dynamic>? extra}) {
    final span = _turnSpan;
    final obs = _obs;
    if (span != null && obs != null) {
      obs.endSpan(span, extra: extra);
      if (obs.activeSpan == span) obs.activeSpan = null;
      _turnSpan = null;
    }
  }

  /// Materialises any buffered streaming reasoning into a [EntryKind.thinking]
  /// block and clears the buffer. Called at every transition where thinking
  /// gives way to something else: assistant text, a tool call, or the end of
  /// the turn.
  void _flushThinking() {
    if (_streamingThinking.isEmpty) return;
    _blocks.add(ConversationEntry.thinking(_streamingThinking));
    _streamingThinking = '';
  }

  void _startAgent(String displayMessage, {String? expandedMessage}) {
    _blocks.add(
        ConversationEntry.user(displayMessage, expandedText: expandedMessage));
    _mode = AppMode.streaming;
    _startSpinner();
    _streamingText = '';
    _streamingThinking = '';
    _subagentGroups.clear();
    _render();

    _turnSpan = _obs?.startSpan(
      'agent.turn',
      kind: 'agent',
      attributes: {
        'openinference.span.kind': 'AGENT',
        'session.id': _sessionManager.currentSessionId ?? '',
        'llm.model_name': _modelId,
        'process.command': 'interactive',
        'user.message_length': displayMessage.length,
        'input.value': redactBody(expandedMessage ?? displayMessage),
      },
    );
    if (_turnSpan != null) _obs!.activeSpan = _turnSpan;

    final stream = agent.run(expandedMessage ?? displayMessage);
    _agentSub = stream.listen(
      _handleAgentEvent,
      onError: (Object e) {
        _endTurnSpan(extra: {'error': e.toString()});
        _blocks.add(ConversationEntry.error(e.toString()));
        _stopSpinner();
        _mode = AppMode.idle;
        _render();
      },
      onDone: () {
        _endTurnSpan();
        if (_streamingText.isNotEmpty) {
          _blocks.add(ConversationEntry.assistant(_streamingText));
          _streamingText = '';
        }
        _stopSpinner();
        _mode = AppMode.idle;
        _render();
      },
    );
  }

  void _handleAgentEvent(AgentEvent event) {
    switch (event) {
      case AgentTextDelta(:final delta):
        // Thinking → answer transition: materialise the reasoning block
        // before any user-visible answer text starts streaming.
        _flushThinking();
        _streamingText += delta;
        _render();

      case AgentThinkingDelta(:final delta):
        _streamingThinking += delta;
        _render();

      case AgentToolCallPending(:final id, :final name):
        // Flush any accumulated reasoning + assistant text so the ordering
        // in _blocks matches the actual conversation flow.
        _flushThinking();
        if (_streamingText.isNotEmpty) {
          _sessionManager
              .logEvent('assistant_message', {'text': _streamingText});
          _blocks.add(ConversationEntry.assistant(_streamingText));
          _streamingText = '';
        }
        _toolUi[id] = _ToolCallUiState(id: id, name: name);
        _blocks.add(ConversationEntry.toolCallRef(id));

        // Early confirmation — ask before arguments finish streaming.
        if (_permissionGate.needsEarlyConfirmation(name)) {
          _toolUi[id]?.phase = _ToolPhase.awaitingApproval;
          _stopSpinner();
          _mode = AppMode.confirming;
          _activeModal = ConfirmModal(
            title: 'Allow $name?',
            bodyLines: ['(arguments still streaming…)'],
            choices: [
              const ModalChoice('Yes', 'y'),
              const ModalChoice('No', 'n'),
              const ModalChoice('Always', 'a'),
            ],
          );
          _render();

          _activeModal!.result.then((choiceIndex) {
            _activeModal = null;
            final span = _obs?.startSpan(
              'tool.approval',
              kind: 'tool.approval',
              attributes: {
                'openinference.span.kind': 'TOOL',
                'tool_call.id': id,
                'tool.name': name,
                'tool.approval.stage': 'early',
                'tool.approval.choice': choiceIndex,
              },
            );
            if (span != null) {
              span.setStatus('ok');
              _obs!.endSpan(span);
            }
            switch (choiceIndex) {
              case 0: // Yes
                _earlyApprovedIds.add(id);
                _toolUi[id]?.phase = _ToolPhase.preparing;
                _mode = AppMode.streaming;
                _startSpinner();
                _render();
              case 2: // Always
                _persistTrustedTool(name);
                _earlyApprovedIds.add(id);
                _toolUi[id]?.phase = _ToolPhase.preparing;
                _mode = AppMode.streaming;
                _startSpinner();
                _render();
              default: // No
                _cancelAgent();
                agent.completeToolCall(ToolResult.denied(id));
            }
          });
          return;
        }

        _render();

      case AgentToolCall(:final call):
        _flushThinking();
        final uiState = _toolUi[call.id];
        if (uiState != null) {
          uiState.args = call.arguments;
        } else {
          // Ollama path — no prior pending event, create the ref now.
          if (_streamingText.isNotEmpty) {
            _blocks.add(ConversationEntry.assistant(_streamingText));
            _streamingText = '';
          }
          _toolUi[call.id] = _ToolCallUiState(
            id: call.id,
            name: call.name,
            phase: _ToolPhase.preparing,
          )..args = call.arguments;
          _blocks.add(ConversationEntry.toolCallRef(call.id));
        }

        _ensureSessionStore();
        _sessionManager.logEvent('tool_call', {
          'id': call.id,
          'name': call.name,
          'arguments': call.arguments,
        });

        // Early-approved at ToolCallPending time — re-check with full args.
        if (_earlyApprovedIds.remove(call.id)) {
          final approval = _permissionGate.resolve(call);
          if (approval == PermissionDecision.allow) {
            _approveTool(call);
            return;
          }
          // Full arguments may still change the decision, so fall through.
        }

        // Permission-based approval.
        switch (_permissionGate.resolve(call)) {
          case PermissionDecision.allow:
            _traceToolApproval(call, 'allow');
            _approveTool(call);
          case PermissionDecision.deny:
            _traceToolApproval(call, 'deny');
            _denyTool(call);
          case PermissionDecision.ask:
            _showToolConfirmModal(call);
        }

      case AgentToolResult(:final result):
        _toolUi[result.callId]?.phase = _ToolPhase.done;
        _sessionManager.logEvent('tool_result', {
          'call_id': result.callId,
          'content': result.content,
          if (result.summary != null) 'summary': result.summary,
          if (result.metadata.isNotEmpty) 'metadata': result.metadata,
        });
        _blocks.add(
            ConversationEntry.toolResult(result.summary ?? result.content));
        _mode = AppMode.streaming;
        _startSpinner();
        _render();

      case AgentUsage(:final usage):
        // Forward main-agent token usage to the session log so resumes and
        // /share output reflect cumulative cost.
        _sessionManager.recordUsage(
          UsageStats()..record(usage),
          role: 'main',
        );

      case AgentDone():
        _flushThinking();
        if (_streamingText.isNotEmpty) {
          _ensureSessionStore();
          _sessionManager
              .logEvent('assistant_message', {'text': _streamingText});
          _blocks.add(ConversationEntry.assistant(_streamingText));
          _streamingText = '';
        }
        _reevaluateTitle();
        _stopSpinner();
        _mode = AppMode.idle;
        _render();

      case AgentError(:final error):
        _blocks.add(ConversationEntry.error(error.toString()));
        _stopSpinner();
        _mode = AppMode.idle;
        _render();
    }
  }

  Future<void> _executeAndCompleteTool(ToolCall call) async {
    try {
      final result = await agent.executeTool(call);
      agent.completeToolCall(result);
    } catch (e) {
      agent.completeToolCall(ToolResult(
        callId: call.id,
        content: 'Tool error: $e',
        success: false,
      ));
    }
  }

  void _cancelAgent() {
    _agentSub?.cancel();
    _endTurnSpan(extra: {'cancelled': true});
    // Stop the spinner before flipping mode — otherwise the timer keeps
    // repainting the status bar even though nothing is happening.
    _stopSpinner();
    _mode = AppMode.idle;
    if (_streamingText.isNotEmpty) {
      _blocks.add(ConversationEntry.assistant('$_streamingText\n[cancelled]'));
      _streamingText = '';
    }
    for (final state in _toolUi.values) {
      if (state.phase == _ToolPhase.preparing ||
          state.phase == _ToolPhase.awaitingApproval ||
          state.phase == _ToolPhase.running) {
        // The tool never completed cleanly — but it wasn't an intrinsic tool
        // error either. Use the dedicated cancelled phase so the transcript
        // doesn't misleadingly read as a failure. awaitingApproval covers the
        // case where the user cancelled while the approval modal was open.
        state.phase = _ToolPhase.cancelled;
      }
    }
    agent.ensureToolResultsComplete();
    _render();
  }

  void _persistTrustedTool(String name) {
    _autoApprovedTools.add(name);
    try {
      final store = ConfigStore(_environment.configPath);
      store.update((c) {
        final tools = (c['trusted_tools'] as List?)?.cast<String>() ?? [];
        if (!tools.contains(name)) {
          tools.add(name);
          c['trusted_tools'] = tools;
        }
      });
    } catch (_) {}
  }

  void _approveTool(ToolCall call) {
    _toolUi[call.id]?.phase = _ToolPhase.running;
    _stopSpinner();
    _mode = AppMode.toolRunning;
    _render();
    _executeAndCompleteTool(call);
  }

  void _denyTool(ToolCall call) {
    _toolUi[call.id]?.phase = _ToolPhase.denied;
    _mode = AppMode.streaming;
    _startSpinner();
    agent.completeToolCall(ToolResult.denied(call.id));
    _render();
  }

  void _showToolConfirmModal(ToolCall call) {
    _toolUi[call.id]?.phase = _ToolPhase.awaitingApproval;
    _stopSpinner();
    _mode = AppMode.confirming;
    final bodyLines =
        call.arguments.entries.map((e) => '${e.key}: ${e.value}').toList();
    if (bodyLines.isEmpty) bodyLines.add('(no arguments)');
    _activeModal = ConfirmModal(
      title: 'Approve tool: ${call.name}',
      bodyLines: bodyLines,
      choices: [
        const ModalChoice('Yes', 'y'),
        const ModalChoice('No', 'n'),
        const ModalChoice('Always', 'a'),
      ],
    );
    _render();

    _activeModal!.result.then((choiceIndex) {
      _activeModal = null;
      switch (choiceIndex) {
        case 0: // Yes
          _traceToolApproval(call, 'allow');
          _approveTool(call);
        case 2: // Always
          _persistTrustedTool(call.name);
          _traceToolApproval(call, 'always');
          _approveTool(call);
        default: // No
          _traceToolApproval(call, 'deny');
          _denyTool(call);
      }
    });
  }

  void _traceToolApproval(ToolCall call, String decision) {
    final span = _obs?.startSpan(
      'tool.approval',
      kind: 'tool.approval',
      attributes: {
        'openinference.span.kind': 'TOOL',
        'tool_call.id': call.id,
        'tool.name': call.name,
        'tool.approval.decision': decision,
      },
    );
    if (span == null) return;
    span.setStatus('ok');
    _obs!.endSpan(span);
  }

  // ── Session runtime (print mode, titling, resume) ──────────────────────

  Future<void> _runPrintMode() async {
    // Two-press SIGINT installed early so it covers stdin draining and any
    // setup work below. First press cancels the in-flight agent stream so we
    // can emit a clean JSON envelope (or a [cancelled] marker) and exit 130;
    // a second press during teardown calls exit(130) directly — that bypasses
    // the finally block intentionally (force-quit semantics, even at the cost
    // of a half-flushed otel span). See docs/reference/sigint-handling.md.
    var cancelled = false;
    var sigintCount = 0;
    StreamIterator<AgentEvent>? agentIter;
    late final StreamSubscription<ProcessSignal> sigintSub;

    sigintSub = ProcessSignal.sigint.watch().listen((_) {
      sigintCount++;
      if (sigintCount == 1) {
        stderr.writeln('\nCancelling… press Ctrl+C again to force quit.');
        cancelled = true;
        agentIter?.cancel();
      } else {
        sigintSub.cancel();
        exit(130);
      }
    });

    final assistantText = StringBuffer();
    final conversationLog = <Map<String, dynamic>>[];
    ObservabilitySpan? turnSpan;
    String expanded = '';

    try {
      if (_resumeSessionId != null) {
        if (_resumeSessionId.isEmpty) {
          stderr.writeln(
              'Error: --print does not support bare --resume; pass a session ID.');
          return;
        }
        final sessions = _sessionManager.listSessions();
        final match =
            sessions.where((s) => s.id.value == _resumeSessionId).toList();
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
      expanded = expandFileRefs(fullPrompt);

      _sessionManager.logEvent('user_message', {'text': expanded});

      turnSpan = _obs?.startSpan(
        'agent.turn',
        kind: 'agent',
        attributes: {
          'openinference.span.kind': 'AGENT',
          'session.id': _sessionManager.currentSessionId ?? '',
          'llm.model_name': _modelId,
          'process.command': 'print',
          'user.message_length': expanded.length,
          'input.value': redactBody(expanded),
        },
      );
      if (turnSpan != null) _obs!.activeSpan = turnSpan;

      agentIter = StreamIterator(agent.run(expanded));
      loop:
      while (await agentIter.moveNext()) {
        final event = agentIter.current;
        switch (event) {
          case AgentTextDelta(:final delta):
            assistantText.write(delta);
            if (!_jsonMode) stdout.write(delta);

          case AgentUsage(:final usage):
            _sessionManager.recordUsage(
              UsageStats()..record(usage),
              role: 'main',
            );

          case AgentToolCall(:final call):
            conversationLog.add({
              'type': 'tool_call',
              'name': call.name,
              'arguments': call.arguments,
            });
            try {
              final result = await agent.executeTool(call);
              agent.completeToolCall(result);
            } catch (e) {
              agent.completeToolCall(ToolResult(
                callId: call.id,
                content: 'Tool error: $e',
                success: false,
              ));
            }

          case AgentDone():
            break loop;

          case AgentError(:final error):
            if (turnSpan != null && turnSpan.endTime == null) {
              _obs!.endSpan(turnSpan, extra: {
                'error': true,
                'error.type': error.runtimeType.toString(),
                'error.message': error.toString(),
              });
              turnSpan = null;
            }
            stderr.writeln(error);
            return;

          default:
            break;
        }
      }

      final text = assistantText.toString();
      if (!_jsonMode && !text.endsWith('\n')) stdout.writeln();

      _sessionManager.logEvent('assistant_message', {'text': text});

      if (_jsonMode) {
        final sessionId = _sessionManager.currentSessionId;
        conversationLog.insert(0, {'type': 'user_message', 'text': expanded});
        conversationLog.add({'type': 'assistant_message', 'text': text});

        final output = {
          'session_id': sessionId,
          'model': _modelId,
          'conversation': conversationLog,
          if (cancelled) 'cancelled': true,
        };
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
      }
    } catch (e) {
      if (turnSpan != null && turnSpan.endTime == null) {
        _obs!.endSpan(turnSpan, extra: {
          'error': true,
          'error.type': e.runtimeType.toString(),
          'error.message': e.toString(),
        });
        turnSpan = null;
      }
      stderr.writeln('Error: $e');
    } finally {
      await agentIter?.cancel();
      await sigintSub.cancel();
      if (turnSpan != null) {
        final obs = _obs!;
        if (turnSpan.endTime == null) {
          obs.endSpan(turnSpan, extra: {
            'output.value': redactBody(assistantText.toString()),
            'output.length': assistantText.length,
            if (cancelled) 'cancelled': true,
          });
        }
        if (obs.activeSpan == turnSpan) obs.activeSpan = null;
      }
      for (final tool in agent.tools.values) {
        try {
          await tool.dispose();
        } catch (_) {}
      }
      await _sessionManager.closeCurrent();
      await _obs?.flush();
      await _obs?.close();
      if (cancelled) exitCode = 130;
    }
  }

  void _generateTitle(String userMessage) {
    final llmClient = _createTitleLlmClient();
    if (llmClient == null) return;

    final generator = TitleGenerator(
      llmClient: llmClient,
      onUsage: (usage) => _sessionManager.recordUsage(
        UsageStats()..record(usage),
        role: 'title',
      ),
    );
    _sessionManager.generateTitle(
      userMessage: userMessage,
      generate: generator.generate,
    );
  }

  void _reevaluateTitle() {
    if (_sessionManager.titleReevaluationRequested ||
        _sessionManager.titleManuallyOverridden) {
      return;
    }
    final store = _sessionManager.currentStore;
    final meta = store?.meta;
    if (meta == null ||
        meta.titleSource != SessionTitleSource.auto ||
        meta.titleState != SessionTitleState.provisional ||
        meta.titleGenerationCount >= 2) {
      return;
    }

    String? firstUserMessage;
    String? latestUserMessage;
    String? firstAssistantMessage;
    String? latestAssistantMessage;
    final toolNames = <String>[];
    for (final message in agent.conversation) {
      switch (message.role) {
        case Role.user:
          final text = message.text;
          if (text == null || text.isEmpty) continue;
          firstUserMessage ??= text;
          latestUserMessage = text;
        case Role.assistant:
          final text = message.text;
          if (text != null && text.isNotEmpty) {
            firstAssistantMessage ??= text;
            latestAssistantMessage = text;
          }
          for (final toolCall in message.toolCalls) {
            toolNames.add(toolCall.name);
          }
        case Role.toolResult:
          break;
      }
    }

    final hasEnoughContext = (firstAssistantMessage != null &&
            firstAssistantMessage.trim().length >= 40) ||
        toolNames.isNotEmpty ||
        firstUserMessage != null &&
            latestUserMessage != null &&
            firstUserMessage != latestUserMessage;
    if (!hasEnoughContext) return;

    final llmClient = _createTitleLlmClient();
    if (llmClient == null) return;
    _sessionManager.titleReevaluationRequested = true;
    final generator = TitleGenerator(
      llmClient: llmClient,
      onUsage: (usage) => _sessionManager.recordUsage(
        UsageStats()..record(usage),
        role: 'title',
      ),
    );
    _sessionManager.reevaluateTitle(
      context: TitleContext(
        firstUserMessage: firstUserMessage,
        latestUserMessage: latestUserMessage,
        firstAssistantMessage: firstAssistantMessage,
        latestAssistantMessage: latestAssistantMessage,
        toolNames: toolNames,
        cwdBasename: _cwd.split(Platform.pathSeparator).last,
      ),
      generate: generator.generateFromContext,
    );
  }

  LlmClient? _createTitleLlmClient() {
    final config = _config;
    final factory = _llmFactory;
    if (config == null || factory == null) return null;

    if (!config.titleGenerationEnabled) {
      if (config.observability.debug) {
        stderr.writeln('[debug] title generation disabled; skipping');
      }
      return null;
    }

    final target = _resolveTitleTarget(config);
    try {
      return factory.createFor(
        target.ref,
        systemPrompt: TitleGenerator.systemPrompt,
      );
    } on ConfigError {
      // No adapter or missing credentials for the small model — skip titling.
      return null;
    }
  }

  void _ensureSessionStore() {
    final config = _config;
    _sessionManager.ensureSessionStore(
      cwd: _cwd,
      modelRef: config?.activeModel.toString() ?? _modelId,
    );
  }

  /// Resume [session] into the running app. Used by startup paths
  /// (`--resume <id>`, bare `--resume`). The interactive `/resume` command
  /// composes the same primitives directly via [_conversation] —
  /// duplication is deliberate; each call site is self-contained.
  String _resumeSession(SessionMeta session) {
    final result =
        _sessionManager.resumeSession(session: session, agent: agent);
    _conversation.resetForReplay();
    _sessionManager
      ..titleInitialRequested = session.title != null
      ..titleReevaluationRequested =
          session.titleState == SessionTitleState.stable ||
              session.titleGenerationCount >= 2
      ..titleManuallyOverridden =
          session.titleSource == SessionTitleSource.user;

    _conversation.notify(
      'Resuming session ${session.id} '
      '(${session.modelRef}, ${session.startTime.timeAgo})',
    );

    if (!result.hasConversation) {
      return 'Session ${session.id} has no conversation data.';
    }

    final usage = result.replay.totalUsage;
    if (usage.totalCalls > 0) {
      final summary = StringBuffer(
          'Carry-over: ${formatCompactTokens(usage.totalTokens)} tokens '
          'over ${usage.totalCalls} call${usage.totalCalls == 1 ? '' : 's'}');
      final hit = usage.cacheHitRate;
      if (hit != null &&
          (usage.totalCacheRead > 0 || usage.totalCacheWrite > 0)) {
        summary.write(' · ${(hit * 100).toStringAsFixed(0)}% cached');
      }
      summary.write('. Run /usage for the per-role breakdown.');
      _conversation.notify(summary.toString());
    }

    _conversation.appendReplayEntries(result.replay.entries);

    final firstUserMessage = result.replay.firstUserMessage;
    if (!_sessionManager.titleInitialRequested &&
        !_sessionManager.titleManuallyOverridden &&
        firstUserMessage != null &&
        firstUserMessage.isNotEmpty) {
      _sessionManager.titleInitialRequested = true;
      _generateTitle(firstUserMessage);
    }

    return result.message;
  }

  // ── Shell runtime (bash mode + background jobs) ────────────────────────

  void _handleBashSubmit(String text) {
    if (text.isEmpty) return;

    if (text.startsWith('& ') || text == '&') {
      final command = text.substring(1).trim();
      if (command.isEmpty) return;
      _startBackgroundJob(command);
      return;
    }

    _mode = AppMode.bashRunning;
    _render();
    _runBlockingBash(text);
  }

  Future<void> _runBlockingBash(String command) async {
    final span = _obs?.startSpan(
      'shell.command',
      kind: 'shell.command',
      attributes: {
        'process.command': redactBody(command, maxBytes: 8192),
        'process.background': false,
      },
    );
    _bashSpan = span;
    try {
      final running = await _executor.startStreaming(command);
      _bashRunProcess = running.process;

      final stdoutFuture =
          running.stdout.transform(const SystemEncoding().decoder).join();
      final stderrFuture =
          running.stderr.transform(const SystemEncoding().decoder).join();

      final exitCode = await running.exitCode;
      _bashRunProcess = null;

      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;

      final output = StringBuffer();
      if (stdout.isNotEmpty) output.write(stdout);
      if (stderr.isNotEmpty) {
        if (output.isNotEmpty) output.write('\n');
        output.write(stderr);
      }

      final stripped = stripAnsi(output.toString().trimRight());
      _blocks.add(ConversationEntry.bash(command, stripped));
      if (exitCode != 0) {
        _blocks.add(ConversationEntry.system('Exit code: $exitCode'));
      }
      if (span != null && _obs != null && span.endTime == null) {
        _obs.endSpan(span, extra: {
          'process.exit_code': exitCode,
          'process.output_length': stripped.length,
        });
      }
    } catch (e) {
      _bashRunProcess = null;
      _blocks.add(ConversationEntry.error('Bash error: $e'));
      if (span != null && _obs != null && span.endTime == null) {
        _obs.endSpan(span, extra: {
          'error': true,
          'error.type': e.runtimeType.toString(),
          'error.message': e.toString(),
        });
      }
    }
    _bashSpan = null;
    _mode = AppMode.idle;
    _render();
  }

  void _cancelBash() {
    final span = _bashSpan;
    if (span != null && _obs != null && span.endTime == null) {
      _obs.endSpan(span, extra: {
        'cancelled': true,
      });
    }
    _bashSpan = null;
    _bashRunProcess?.kill(ProcessSignal.sigterm);
    _bashRunProcess = null;
    // Mirror the agent-cancel contract: every transition back to idle also
    // stops the spinner, even if this particular path didn't start it.
    _stopSpinner();
    _mode = AppMode.idle;
    _blocks.add(ConversationEntry.system('[bash command cancelled]'));
    _render();
  }

  void _startBackgroundJob(String command) {
    () async {
      try {
        await _jobManager.start(command);
      } catch (e) {
        _blocks.add(ConversationEntry.error('Failed to start job: $e'));
        _render();
      }
    }();
  }

  void _handleJobEvent(JobEvent event) {
    switch (event) {
      case JobStarted(:final id, :final command):
        _blocks.add(ConversationEntry.system('↳ Started job #$id: $command'));
        _render();
      case JobExited(:final id, :final exitCode):
        final job = _jobManager.getJob(id);
        final cmd = job?.command ?? '?';
        final label = exitCode == 0 ? 'exited' : 'failed';
        _blocks.add(
            ConversationEntry.system('↳ Job #$id $label ($exitCode): $cmd'));
        _render();
      case JobError(:final id, :final error):
        _blocks.add(ConversationEntry.system('↳ Job #$id error: $error'));
        _render();
    }
  }

  // ── Subagent updates ───────────────────────────────────────────────────

  void _handleSubagentUpdate(SubagentUpdate update) {
    final groupKey = '${update.task}:${update.index ?? 0}';
    final group = _subagentGroups.putIfAbsent(
      groupKey,
      () {
        final g = SubagentGroup(
          task: update.task,
          index: update.index,
          total: update.total,
        );
        _blocks.add(ConversationEntry.subagentGroup(g));
        return g;
      },
    );

    final prefix =
        update.index != null ? '↳ [${update.index! + 1}/${update.total}]' : '↳';

    switch (update.event) {
      case AgentToolCall(:final call):
        group.currentTool = call.name;
        final argsPreview = call.arguments.entries
            .take(2)
            .map((e) => '${e.key}: ${e.value}')
            .join(', ');
        group.entries
            .add(SubagentEntry('$prefix ▶ ${call.name}  $argsPreview'));
        _render();
      case AgentToolResult(:final result):
        final display = result.summary ??
            (result.content.length > 80
                ? '${result.content.substring(0, 80)}…'
                : result.content);
        group.entries.add(SubagentEntry(
          '$prefix ✓ ${display.replaceAll('\n', ' ')}',
          rawContent: result.summary != null || result.content.length > 80
              ? result.content
              : null,
        ));
        _render();
      case AgentError(:final error):
        group.entries.add(SubagentEntry('$prefix ✗ Error: $error'));
        _render();
      case AgentToolCallPending():
        break;
      case AgentTextDelta():
        break;
      case AgentThinkingDelta():
        // Subagent reasoning isn't rendered in the parent's live UI;
        // matches the AgentRunner policy of dropping it for headless flows.
        break;
      case AgentUsage():
        // Subagent usage is rolled up by AgentManager and persisted via
        // onSubagentUsage. The transient render path doesn't display it.
        break;
      case AgentDone():
        group.done = true;
        group.currentTool = null;
        _render();
    }
  }

  // ── Spinner ────────────────────────────────────────────────────────────

  void _startSpinner() {
    if (_spinnerTimer != null) return;
    _spinnerFrame = 0;
    _spinnerTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      _spinnerFrame = (_spinnerFrame + 1) % _spinnerFrames.length;
      _render();
    });
  }

  void _stopSpinner() {
    _spinnerTimer?.cancel();
    _spinnerTimer = null;
  }

  // ── Misc ───────────────────────────────────────────────────────────────

  void _addSystemMessage(String message) {
    _blocks.add(ConversationEntry.system(message));
  }
}
