import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:glue_core/glue_core.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/terminal/layout.dart';
import 'package:glue/src/input/line_editor.dart' show InputAction;
import 'package:glue/src/input/text_area_editor.dart';
import 'package:glue/src/input/streaming_input_handler.dart';
import 'package:glue/src/input/file_expander.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:glue/src/commands/config_command.dart' show userConfigPath;
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
import 'package:glue/src/app/transcript_selection.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:glue/src/ui/model_panel_formatter.dart'
    show CatalogRow, ModelAvailability;
import 'package:glue/src/rendering/block_renderer.dart';
import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/ui/modal.dart';
import 'package:glue/src/ui/dock_manager.dart';
import 'package:glue/src/ui/toast.dart';
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
  _ToolCallUiState({
    required this.id,
    required this.name,
    this.phase = _ToolPhase.preparing,
  });

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
    '⠏',
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
  late final Toast _toast;
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
  final Future<void> Function()? _runtimeClose;
  final Future<RuntimeDiffOutcome> Function()? _runtimeDiff;

  /// Optional snapshot of runtime info for SessionMeta (Phase 3).
  /// Surfaces use this to persist `runtime_id`, `sandbox_id`,
  /// `runtime_bootstrap_sha`, `runtime_remote_url` so `/resume` and
  /// `glue session …` can reason about prior cloud sessions.
  final RuntimeInfoSnapshot? _runtimeInfo;
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
  RunningCommandHandle? _bashRunHandle;
  ObservabilitySpan? _bashSpan;
  DateTime? _lastCtrlC;

  final Map<String, SubagentGroup> _subagentGroups = {};
  final List<SubagentGroup?> _outputLineGroups = [];

  // Transcript selection. Updated whenever the user drags in the output
  // zone; rebuilt against block-anchored coordinates on every render so
  // streaming and resize don't desync the highlight.
  TranscriptSelection? _selection;
  DragState? _dragState;
  final ClickChain _clickChain = ClickChain();

  // Per-render shadow of the output transcript used for hit-testing and
  // plain-text extraction. Indices align with `outputLines`; entries are
  // null for non-selectable rows (blank separators, modal/panel lines).
  final List<String> _plainOutputLines = [];
  final List<(String blockId, int lineStartOffset)?> _outputLineAnchors = [];
  final Map<String, String> _blockPlainText = {};
  final List<String> _blockOrder = [];

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
    required this._modelId,
    this._manager,
    McpClientPool? mcpPool,
    this._llmFactory,
    GlueConfig? config,
    this._systemPrompt,
    Set<String>? extraTrustedTools,
    SessionStore? sessionStore,
    CommandExecutor? executor,
    this._runtimeClose,
    this._runtimeDiff,
    this._runtimeInfo,
    ShellJobManager? jobManager,
    this._startupContinue = false,
    this._startupPrompt,
    this._printMode = false,
    this._jsonMode = false,
    this._resumeSessionId,
    Observability? obs,
    this._debugController,
    SkillRuntime? skillRuntime,
    Environment? environment,
  }) : _environment = environment ?? Environment.detect(),
       _mcpPool =
           mcpPool ??
           McpClientPool(
             config: const McpConfig(),
             credentials:
                 config?.credentials ??
                 CredentialStore(path: '/dev/null', env: const {}),
           ),
       _config = config,
       _executor = executor ?? HostExecutor(const ShellConfig()),
       _jobManager =
           jobManager ??
           ShellJobManager(
             executor ?? HostExecutor(const ShellConfig()),
             obs: obs,
           ),
       _obs = obs,
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
    _panels = ModalSurface(panelStack: _panelStack, render: _render);
    _toast = Toast(onRender: _render);
    _skillRuntime =
        skillRuntime ??
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
      runtimeClose: services.runtimeSession.close,
      runtimeDiff: services.runtimeSession.diffSinceBootstrap,
      runtimeInfo: RuntimeInfoSnapshot.from(services.runtimeSession),
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

  /// Captures the cloud runtime's workspace diff before shutdown.
  ///
  /// Writes the patch and a `runtime.patch.meta.json` sidecar to the
  /// session directory. Distinguishes three outcomes from the runtime:
  /// success (write + breadcrumb), empty (silent — no changes), and
  /// unavailable (write a single-line warning naming the reason so the
  /// user knows the session didn't silently lose their work).
  ///
  /// Enforces [_runtimePatchSizeCapBytes] (Q2 default: 50 MB) to avoid
  /// blowing up the session directory when an agent vendors deps or
  /// commits generated assets. Truncated patches keep a `.truncated`
  /// suffix so apply-tools won't try to use them as-is.
  ///
  /// Failures are swallowed so shutdown never blocks on diff capture.
  Future<void> _captureRuntimePatch() async {
    final diff = _runtimeDiff;
    final sessionId = _sessionManager.currentSessionId;
    if (diff == null || sessionId == null) return;
    try {
      final outcome = await diff();
      switch (outcome) {
        case RuntimeDiffOutcomeSuccess():
          _writeRuntimePatch(
            sessionId: sessionId,
            patch: outcome.patch,
            meta: outcome.meta,
          );
        case RuntimeDiffOutcomeEmpty():
          // No agent changes inside the sandbox — silent is fine here,
          // there's nothing for the user to act on.
          break;
        case RuntimeDiffOutcomeUnavailable():
          // Don't fall back to silent null — surface why the diff
          // couldn't be captured so the user can act on it. Skip
          // notSupported (host/docker, by design).
          if (outcome.reason != RuntimeDiffUnavailableReason.notSupported) {
            stderr.writeln(
              '\n\x1b[33m◆\x1b[0m Runtime workspace diff unavailable '
              '(${outcome.reason.name})'
              '${outcome.hint == null ? '' : ': ${outcome.hint}'}',
            );
          }
      }
    } catch (_) {
      /* shutdown must not block on diff failure */
    }
  }

  static const int _runtimePatchSizeCapBytes = 50 * 1024 * 1024;

  void _writeRuntimePatch({
    required SessionId sessionId,
    required String patch,
    required RuntimeDiffMeta meta,
  }) {
    final sessionDir = _environment.sessionDir(sessionId);
    // Phase 1: capture is now format-patch mbox, not plain `git diff`,
    // so save with the .mbox extension and recommend `git am --3way` for
    // apply. The .meta.json sidecar tells host tools which format to
    // expect.
    final ext = meta.format == 'format-patch' ? 'mbox' : 'patch';
    final patchPath = p.join(sessionDir, 'runtime.$ext');
    final metaPath = p.join(sessionDir, 'runtime.$ext.meta.json');
    final cappedPatch = patch.length > _runtimePatchSizeCapBytes
        ? '${patch.substring(0, _runtimePatchSizeCapBytes)}\n'
              '<<< truncated: original was ${patch.length} bytes, '
              'cap is $_runtimePatchSizeCapBytes >>>\n'
        : patch;
    final truncated = patch.length > _runtimePatchSizeCapBytes;
    File(
      truncated ? '$patchPath.truncated' : patchPath,
    ).writeAsStringSync(cappedPatch);
    File(metaPath).writeAsStringSync(
      '${jsonEncode({...meta.toJson(), 'truncated': truncated, 'truncation_cap_bytes': _runtimePatchSizeCapBytes})}\n',
    );
    // Phase 3: record the patch path + close time on the session
    // meta so `glue session …` can find it without scanning the
    // filesystem.
    final store = _sessionManager.currentStore;
    if (store != null) {
      store.meta
        ..runtimePatchPath = truncated ? '$patchPath.truncated' : patchPath
        ..runtimeClosedAt = DateTime.now().toUtc();
      store.updateMeta();
    }
    final applyHint = meta.format == 'format-patch'
        ? 'apply with: git am --3way $patchPath'
        : 'apply with: git apply $patchPath';
    if (truncated) {
      stderr.writeln(
        '\n\x1b[33m◆\x1b[0m Runtime workspace diff was ${patch.length} '
        'bytes (cap: $_runtimePatchSizeCapBytes); '
        'truncated copy saved to $patchPath.truncated',
      );
    } else {
      stderr.writeln(
        '\n\x1b[36m◆\x1b[0m Runtime workspace diff saved to $patchPath\n'
        '  $applyHint',
      );
    }
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

    _blocks.add(
      ConversationEntry.system(
        '\x1b[33m◆\x1b[0m Glue v${AppConstants.version} — $_modelId\n'
        'Working directory: ${_environment.shortenPath(_cwd)}\n'
        'Type /help for commands.',
      ),
    );

    final termSub = terminal.events.listen(_handleTerminalEvent);
    final appSub = _events.stream.listen(_handleAppEvent);
    _subagentSub = _manager?.updates.listen(_handleSubagentUpdate);
    final jobSub = _jobManager.events.listen(_handleJobEvent);
    final mcpSub = _mcpPool.events.listen(_handleMcpEvent);

    _render();

    if (_resumeSessionId != null) {
      final sessions = _sessionManager.listSessions();
      if (_resumeSessionId.isEmpty) {
        _commands.execute('/resume');
        _render();
      } else {
        final match = sessions
            .where((s) => s.id.value == _resumeSessionId)
            .toList();
        if (match.isNotEmpty) {
          final result = _resumeSession(match.first);
          if (result.isNotEmpty) {
            _blocks.add(ConversationEntry.system(result));
          }
          _render();
        } else {
          _blocks.add(
            ConversationEntry.system('Session $_resumeSessionId not found.'),
          );
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
      await _captureRuntimePatch();
      await _sessionManager.closeCurrent();
      await _obs?.flush();
      await _obs?.close();
      await jobSub.cancel();
      await _jobManager.shutdown();
      // Tear down the active runtime (e.g. stop a cloud sandbox so the
      // user isn't billed for an idle session). For host/docker this
      // is a no-op.
      if (_runtimeClose != null) {
        try {
          await _runtimeClose();
        } catch (_) {}
      }
      await termSub.cancel();
      await appSub.cancel();
      await mcpSub.cancel();
      await _mcpPool.close();
      await _agentSub?.cancel();
      await _subagentSub?.cancel();
      _toast.dismiss();
      await _events.close();
      terminal.disableMouse();
      terminal.resetScrollRegion();
      terminal.showCursor();
      terminal.write('\x1b[0m');
      terminal.disableAltScreen();
      terminal.disableRawMode();
      final sessionId = _sessionManager.currentSessionId;
      if (sessionId != null) {
        stdout.writeln(
          '\n\x1b[33m◆\x1b[0m Holding it together till next time.',
        );
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
        choices: const [ModalChoice('Yes', 'y'), ModalChoice('No', 'n')],
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
        0,
        _blocks.length - AppConstants.maxConversationBlocks,
      );
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
    _plainOutputLines.clear();
    _outputLineAnchors.clear();
    _blockPlainText.clear();
    _blockOrder.clear();

    void pushBlock({
      required String blockId,
      required String renderedText,
      SubagentGroup? group,
    }) {
      final plain = stripAnsi(renderedText);
      _blockPlainText[blockId] = plain;
      _blockOrder.add(blockId);

      final ansiLines = renderedText.split('\n');
      final plainLines = plain.split('\n');
      // Defensive: ANSI and plain splits should agree on line count; if a
      // renderer ever leaks an ANSI escape across a newline this guards
      // against an index mismatch.
      final lineCount = ansiLines.length < plainLines.length
          ? ansiLines.length
          : plainLines.length;
      var offset = 0;
      for (var i = 0; i < lineCount; i++) {
        outputLines.add(ansiLines[i]);
        _plainOutputLines.add(plainLines[i]);
        _outputLineAnchors.add((blockId, offset));
        _outputLineGroups.add(group);
        offset += plainLines[i].length + 1; // +1 for the joining newline
      }
      // Trailing separator between blocks: not selectable.
      outputLines.add('');
      _plainOutputLines.add('');
      _outputLineAnchors.add(null);
      _outputLineGroups.add(null);
    }

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
        EntryKind.subagentGroup => renderer.renderSubagent(
          block.group!.expanded
              ? '${block.group!.summary}\n${block.group!.entries.map((e) => e.render(expanded: true)).join('\n')}'
              : block.group!.summary,
        ),
        EntryKind.system => renderer.renderSystem(block.text),
        EntryKind.bash => renderer.renderBash(
          block.expandedText ?? 'shell',
          block.text,
          maxLines: _config?.bashMaxLines ?? 50,
        ),
      };
      pushBlock(
        blockId: block.id,
        renderedText: text,
        group: block.kind == EntryKind.subagentGroup ? block.group : null,
      );
    }

    // If streaming reasoning, render it above the (still-empty) assistant
    // text — when both buffers are non-empty (Anthropic interleaves them in
    // edge cases) the user sees thinking "above" the conclusion.
    if (_streamingThinking.isNotEmpty) {
      pushBlock(
        blockId: kStreamingThinkingId,
        renderedText: renderer.renderThinking(_streamingThinking),
      );
    }

    if (_streamingText.isNotEmpty) {
      pushBlock(
        blockId: kStreamingAssistantId,
        renderedText: renderer.renderAssistant(_streamingText),
      );
    }

    if (_activeModal != null && !_activeModal!.isComplete) {
      // Modal rows are not part of the selectable transcript.
      outputLines.add('');
      _plainOutputLines.add('');
      _outputLineAnchors.add(null);
      _outputLineGroups.add(null);
      for (final line in _activeModal!.render(layout.outputWidth)) {
        outputLines.add(line);
        _plainOutputLines.add(stripAnsi(line));
        _outputLineAnchors.add(null);
        _outputLineGroups.add(null);
      }
    }

    outputLines.add('');
    _plainOutputLines.add('');
    _outputLineAnchors.add(null);
    _outputLineGroups.add(null);

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

    final firstLine = (totalLines - viewportHeight - _scrollOffset).clamp(
      0,
      totalLines,
    );
    final endLine = (firstLine + viewportHeight).clamp(0, totalLines);
    final visibleLines = firstLine < endLine
        ? outputLines.sublist(firstLine, endLine)
        : <String>[];

    _applySelectionToVisibleSlice(visibleLines, firstLine);

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

    // 3c. Transient copy toast — narrow chip anchored top-right with a
    // 2-cell gutter from the output's right edge. Painted as its own
    // small rect so the underlying transcript stays visible around it.
    if (_toast.visible) {
      const gutter = 2;
      final chipWidth = _toast.cellWidth;
      final col = layout.outputRight - chipWidth - gutter + 1;
      if (chipWidth > 0 && col >= layout.outputLeft) {
        layout.paintRect(
          row: layout.outputTop,
          col: col,
          width: chipWidth,
          height: 1,
          lines: [_toast.renderLine()],
        );
      }
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
    final mcpUnhealthy = _mcpPool.unhealthyCount;
    final mcpSeg = mcpUnhealthy > 0 ? 'MCP:$mcpUnhealthy⚠' : null;
    final rightSegs = [
      formatStatusModelLabel(
        _config?.activeModel,
        _config?.catalogData,
        _modelId,
      ),
      modeLabel,
      ansiTruncate(shortCwd, 30),
      ?scrollSeg,
      ?mcpSeg,
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

  // ── Transcript selection ───────────────────────────────────────────────

  /// Translate a screen `(x, y)` (1-indexed cells) into a position in the
  /// transcript, or `null` if the point is outside the selectable output
  /// zone or lands on a non-selectable row (blank separator, modal).
  TranscriptPosition? _resolvePositionAt(int x, int y) {
    if (y < layout.outputTop || y > layout.outputBottom) return null;
    final viewportHeight = layout.outputBottom - layout.outputTop + 1;
    final totalLines = _outputLineAnchors.length;
    final firstLine = (totalLines - viewportHeight - _scrollOffset).clamp(
      0,
      totalLines,
    );
    final visibleIdx = firstLine + (y - layout.outputTop);
    if (visibleIdx < 0 || visibleIdx >= totalLines) return null;
    final anchor = _outputLineAnchors[visibleIdx];
    if (anchor == null) return null;
    final (blockId, lineStartOffset) = anchor;
    final plain = _plainOutputLines[visibleIdx];
    final col = (x - layout.outputLeft).clamp(0, 1 << 30);
    final charOffsetInLine = _colToCharOffset(plain, col);
    return TranscriptPosition(
      blockId: blockId,
      plainTextOffset: lineStartOffset + charOffsetInLine,
    );
  }

  /// Walk [plainLine] in display cells and return the char offset at the
  /// start of the cell that contains [col]. Out-of-range `col` clamps to
  /// the end of the line.
  int _colToCharOffset(String plainLine, int col) {
    var visible = 0;
    var i = 0;
    while (i < plainLine.length) {
      final cu = plainLine.codeUnitAt(i);
      int cp;
      int adv;
      if (cu >= 0xD800 && cu <= 0xDBFF && i + 1 < plainLine.length) {
        final lo = plainLine.codeUnitAt(i + 1);
        cp = 0x10000 + ((cu - 0xD800) << 10) + (lo - 0xDC00);
        adv = 2;
      } else {
        cp = cu;
        adv = 1;
      }
      final w = charWidth(cp);
      if (visible >= col) return i;
      if (visible + w > col) return i;
      visible += w;
      i += adv;
    }
    return plainLine.length;
  }

  /// Inverse of [_colToCharOffset]: char offset → display column.
  int _charOffsetToCol(String plainLine, int charOffset) {
    var visible = 0;
    var i = 0;
    final limit = charOffset > plainLine.length ? plainLine.length : charOffset;
    while (i < limit) {
      final cu = plainLine.codeUnitAt(i);
      int cp;
      int adv;
      if (cu >= 0xD800 && cu <= 0xDBFF && i + 1 < plainLine.length) {
        final lo = plainLine.codeUnitAt(i + 1);
        cp = 0x10000 + ((cu - 0xD800) << 10) + (lo - 0xDC00);
        adv = 2;
      } else {
        cp = cu;
        adv = 1;
      }
      visible += charWidth(cp);
      i += adv;
    }
    return visible;
  }

  /// Rewrite [visibleLines] in place to wrap any selected cells with the
  /// reverse-video escape. Called from [_render] immediately before
  /// [Layout.paintOutputViewport] so the layout API stays string-only.
  void _applySelectionToVisibleSlice(List<String> visibleLines, int firstLine) {
    final sel = _selection;
    if (sel == null || sel.isEmpty) return;
    final ordered = sel.ordered(_blockOrder);
    if (ordered == null) {
      // Selection points at a block that no longer exists in this render —
      // drop the selection rather than guessing where it should go.
      _selection = null;
      return;
    }
    final (start, end) = ordered;
    final indexOf = <String, int>{};
    for (var i = 0; i < _blockOrder.length; i++) {
      indexOf[_blockOrder[i]] = i;
    }
    final startBlockIdx = indexOf[start.blockId]!;
    final endBlockIdx = indexOf[end.blockId]!;

    for (var i = 0; i < visibleLines.length; i++) {
      final absIdx = firstLine + i;
      if (absIdx < 0 || absIdx >= _outputLineAnchors.length) continue;
      final anchor = _outputLineAnchors[absIdx];
      if (anchor == null) continue;
      final (blockId, lineStartOffset) = anchor;
      final blockIdx = indexOf[blockId];
      if (blockIdx == null) continue;
      if (blockIdx < startBlockIdx || blockIdx > endBlockIdx) continue;

      final plain = _plainOutputLines[absIdx];
      final lineLen = plain.length;
      var lineStartCharOffset = 0;
      var lineEndCharOffset = lineLen;

      if (blockIdx == startBlockIdx) {
        final relStart = start.plainTextOffset - lineStartOffset;
        if (relStart >= lineLen + 1) continue; // start is past this line
        if (relStart > 0) lineStartCharOffset = relStart;
      }
      if (blockIdx == endBlockIdx) {
        final relEnd = end.plainTextOffset - lineStartOffset;
        if (relEnd <= 0) continue; // end is before this line
        if (relEnd < lineLen) lineEndCharOffset = relEnd;
      }

      final startCol = _charOffsetToCol(plain, lineStartCharOffset);
      final endCol = _charOffsetToCol(plain, lineEndCharOffset);
      if (endCol <= startCol) continue;
      visibleLines[i] = applySelectionHighlight(
        visibleLines[i],
        startCol,
        endCol,
      );
    }
  }

  /// Extract the plain-text representation of the current selection,
  /// honoring line breaks. Returns an empty string if the selection is
  /// empty, the blocks have disappeared, or no text falls inside the
  /// selected range.
  String _extractSelectedText() {
    final sel = _selection;
    if (sel == null || sel.isEmpty) return '';
    final ordered = sel.ordered(_blockOrder);
    if (ordered == null) return '';
    final (start, end) = ordered;
    final indexOf = <String, int>{};
    for (var i = 0; i < _blockOrder.length; i++) {
      indexOf[_blockOrder[i]] = i;
    }
    final startBlockIdx = indexOf[start.blockId]!;
    final endBlockIdx = indexOf[end.blockId]!;

    final buf = StringBuffer();
    for (var bi = startBlockIdx; bi <= endBlockIdx; bi++) {
      final id = _blockOrder[bi];
      final plain = _blockPlainText[id];
      if (plain == null) continue;
      var lo = 0;
      var hi = plain.length;
      if (bi == startBlockIdx) {
        lo = start.plainTextOffset.clamp(0, plain.length);
      }
      if (bi == endBlockIdx) hi = end.plainTextOffset.clamp(0, plain.length);
      if (hi <= lo) continue;
      if (buf.isNotEmpty) buf.write('\n');
      buf.write(plain.substring(lo, hi));
    }
    return buf.toString().trimRight();
  }

  /// Clear any active selection and request a re-render.
  void _clearSelection() {
    if (_selection == null) return;
    _selection = null;
    _render();
  }

  /// Whether a non-empty selection is currently held.
  bool get hasSelection => _selection != null && !_selection!.isEmpty;

  /// Copy the current selection to the clipboard. Used by both the
  /// mouse-release path and the Ctrl+Shift+C keyboard shortcut. The
  /// selection itself stays highlighted (Esc or a new drag clears it).
  ///
  /// Confirmation surfaces through [_toast] — a transient top-right chip
  /// painted directly into the output viewport — so the permanent
  /// transcript stays free of "Copied …" noise.
  Future<void> copySelectionToClipboard() async {
    final text = _extractSelectedText();
    if (text.isEmpty) return;
    final ok = await copyToClipboard(text);
    if (!ok) {
      _toast.show('Clipboard unavailable', kind: ToastKind.error);
      return;
    }
    final lineCount = '\n'.allMatches(text).length + 1;
    _toast.show(
      lineCount == 1
          ? 'Copied ${text.length} chars'
          : 'Copied $lineCount lines',
    );
  }

  /// Migrate any selection that points at a streaming sentinel onto a
  /// freshly-flushed block. The plain-text rendering of the new block is
  /// the streaming buffer's content unchanged, so existing offsets still
  /// point at the same characters.
  void _rebindStreamingSelection(String fromSentinel, String toBlockId) {
    final sel = _selection;
    if (sel == null) return;
    _selection = sel.rebindBlockId(fromSentinel, toBlockId);
  }

  /// Mouse routing: wheel → scroll; press/motion/release → drag selection
  /// in the output zone; click-to-expand (subagent groups) is the
  /// fallback when a press-release pair didn't cross the drag threshold.
  ///
  /// Shift-modified events are ignored on purpose — most terminals honour
  /// Shift-drag as a native-selection bypass even while application mouse
  /// capture is on, and reacting here would steal that escape hatch.
  void _handleMouseEvent(MouseEvent event) {
    if (event.isScroll) {
      _events.add(UserScroll(event.isScrollUp ? 3 : -3));
      return;
    }
    if (event.shift) {
      // Cancel any in-progress drag and let the terminal handle it.
      _dragState = null;
      return;
    }
    // Only react to the primary (left) button.
    if (event.buttonNumber != 0) return;

    if (event.isMotion && event.isDown) {
      _handleMouseMotion(event);
      return;
    }
    if (event.isDown) {
      _handleMousePress(event);
      return;
    }
    _handleMouseRelease(event);
  }

  void _handleMousePress(MouseEvent event) {
    final inOutput =
        event.y >= layout.outputTop && event.y <= layout.outputBottom;
    if (!inOutput) {
      _dragState = null;
      return;
    }
    // Starting a new gesture clears any previous selection so the
    // highlight doesn't linger while the user picks a new range.
    if (_selection != null) {
      _selection = null;
    }
    final origin = _resolvePositionAt(event.x, event.y);
    if (origin == null) {
      _dragState = null;
      _render();
      return;
    }
    _dragState = DragState(originX: event.x, originY: event.y, origin: origin);
    _render();
  }

  void _handleMouseMotion(MouseEvent event) {
    final drag = _dragState;
    if (drag == null) return;
    final justCrossed = drag.observeMotion(event.x, event.y);
    if (!drag.exceededThreshold) return;
    final focus = _resolvePositionAt(event.x, event.y);
    if (focus == null) return;
    if (justCrossed || _selection == null) {
      _selection = TranscriptSelection(anchor: drag.origin, focus: focus);
    } else {
      _selection = _selection!.withFocus(focus);
    }
    _render();
  }

  void _handleMouseRelease(MouseEvent event) {
    final drag = _dragState;
    _dragState = null;
    if (drag == null) return;
    if (drag.exceededThreshold) {
      // A real drag invalidates any accumulated single-click chain;
      // otherwise a slow drag followed by a quick click would
      // accidentally promote to a double-click.
      _clickChain.reset();
      final endPos = _resolvePositionAt(event.x, event.y);
      if (endPos != null && _selection != null) {
        _selection = _selection!.withFocus(endPos);
      }
      copySelectionToClipboard();
      return;
    }
    // It's a click — feed the chain and dispatch on count.
    final count = _clickChain.register(event.x, event.y, DateTime.now());
    switch (count) {
      case 1:
        _handleOutputClick(event.y);
      case 2:
        _selectWordAt(event.x, event.y);
      case 3:
        _selectLineAt(event.y);
    }
  }

  /// Double-click: select the contiguous same-class run (word / punct
  /// run) containing the click position, then auto-copy.
  void _selectWordAt(int x, int y) {
    final pos = _resolvePositionAt(x, y);
    if (pos == null) return;
    final blockPlain = _blockPlainText[pos.blockId];
    if (blockPlain == null || blockPlain.isEmpty) return;
    final (start, end) = findClassRange(blockPlain, pos.plainTextOffset);
    if (end <= start) return;
    _selection = TranscriptSelection(
      anchor: TranscriptPosition(blockId: pos.blockId, plainTextOffset: start),
      focus: TranscriptPosition(blockId: pos.blockId, plainTextOffset: end),
    );
    copySelectionToClipboard();
  }

  /// Triple-click: select the whole rendered line under the cursor,
  /// then auto-copy.
  void _selectLineAt(int y) {
    if (y < layout.outputTop || y > layout.outputBottom) return;
    final viewportHeight = layout.outputBottom - layout.outputTop + 1;
    final totalLines = _outputLineAnchors.length;
    final firstLine = (totalLines - viewportHeight - _scrollOffset).clamp(
      0,
      totalLines,
    );
    final idx = firstLine + (y - layout.outputTop);
    if (idx < 0 || idx >= _outputLineAnchors.length) return;
    final anchor = _outputLineAnchors[idx];
    if (anchor == null) return;
    final (blockId, lineStartOffset) = anchor;
    final plain = _plainOutputLines[idx];
    if (plain.isEmpty) return;
    _selection = TranscriptSelection(
      anchor: TranscriptPosition(
        blockId: blockId,
        plainTextOffset: lineStartOffset,
      ),
      focus: TranscriptPosition(
        blockId: blockId,
        plainTextOffset: lineStartOffset + plain.length,
      ),
    );
    copySelectionToClipboard();
  }

  void _handleOutputClick(int y) {
    if (y < layout.outputTop || y > layout.outputBottom) return;
    final viewportHeight = layout.outputBottom - layout.outputTop + 1;
    final totalLines = _outputLineGroups.length;
    final firstLine = (totalLines - viewportHeight - _scrollOffset).clamp(
      0,
      totalLines,
    );
    final idx = firstLine + (y - layout.outputTop);
    if (idx < 0 || idx >= _outputLineGroups.length) return;
    final group = _outputLineGroups[idx];
    if (group == null) return;
    group.expanded = !group.expanded;
    _render();
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

        // Transcript selection takes priority over normal Esc/copy keys:
        //  - Esc clears an active selection without falling through to
        //    cancel-agent or dismiss-autocomplete.
        //  - Ctrl+Shift+C copies the current selection. We never override
        //    Ctrl+C because that must stay reserved for cancelling an
        //    in-flight agent (users often select text *because* the agent
        //    is misbehaving and they want to abort).
        if (event case KeyEvent(key: Key.escape) when hasSelection) {
          _clearSelection();
          return;
        }
        if (event case KeyEvent(key: Key.ctrlShiftC)) {
          if (hasSelection) copySelectionToClipboard();
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
            final isEnterOnExactMatch =
                isEnter &&
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
              _blocks.add(
                ConversationEntry.system('Press Ctrl+C again to exit.'),
              );
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

      case final MouseEvent mouse:
        _handleMouseEvent(mouse);

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
    final entry = ConversationEntry.thinking(_streamingThinking);
    _blocks.add(entry);
    _rebindStreamingSelection(kStreamingThinkingId, entry.id);
    _streamingThinking = '';
  }

  /// Flush the streaming-assistant buffer into a real block, carrying any
  /// active transcript selection across the sentinel→entry handoff. All
  /// places that previously wrote `_blocks.add(ConversationEntry.assistant(...))`
  /// for the streaming buffer go through this helper.
  void _flushAssistant({String? overrideText}) {
    final text = overrideText ?? _streamingText;
    final entry = ConversationEntry.assistant(text);
    _blocks.add(entry);
    _rebindStreamingSelection(kStreamingAssistantId, entry.id);
    _streamingText = '';
  }

  void _startAgent(String displayMessage, {String? expandedMessage}) {
    _blocks.add(
      ConversationEntry.user(displayMessage, expandedText: expandedMessage),
    );
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
          _flushAssistant();
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
          _sessionManager.logEvent('assistant_message', {
            'text': _streamingText,
          });
          _flushAssistant();
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
            _flushAssistant();
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
          ConversationEntry.toolResult(result.summary ?? result.content),
        );
        _mode = AppMode.streaming;
        _startSpinner();
        _render();

      case AgentUsage(:final usage):
        // Forward main-agent token usage to the session log so resumes and
        // /share output reflect cumulative cost.
        _sessionManager.recordUsage(UsageStats()..record(usage), role: 'main');

      case AgentDone():
        _flushThinking();
        if (_streamingText.isNotEmpty) {
          _ensureSessionStore();
          _sessionManager.logEvent('assistant_message', {
            'text': _streamingText,
          });
          _flushAssistant();
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

      case AgentNotice(:final message, :final kind):
        // Soft-degradation announcement: routed through the existing
        // system-message rendering (gray, single-line) with a marker
        // glyph prefix so the user notices it scroll past. Persists into
        // the session log for replay/share visibility.
        final glyph = kind == 'warning' ? '!' : '·';
        _blocks.add(ConversationEntry.system('$glyph $message'));
        _sessionManager.logEvent('agent_notice', {
          'kind': kind,
          'message': message,
        });
        _render();
    }
  }

  Future<void> _executeAndCompleteTool(ToolCall call) async {
    try {
      final result = await agent.executeTool(call);
      agent.completeToolCall(result);
    } catch (e) {
      agent.completeToolCall(
        ToolResult(callId: call.id, content: 'Tool error: $e', success: false),
      );
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
      _flushAssistant(overrideText: '$_streamingText\n[cancelled]');
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
    final bodyLines = call.arguments.entries
        .map((e) => '${e.key}: ${e.value}')
        .toList();
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
            'Error: --print does not support bare --resume; pass a session ID.',
          );
          return;
        }
        final sessions = _sessionManager.listSessions();
        final match = sessions
            .where((s) => s.id.value == _resumeSessionId)
            .toList();
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

      final fullPrompt = App.buildPrintPrompt(
        prompt: prompt,
        stdinContent: stdinContent,
      );
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
              agent.completeToolCall(
                ToolResult(
                  callId: call.id,
                  content: 'Tool error: $e',
                  success: false,
                ),
              );
            }

          case AgentDone():
            break loop;

          case AgentError(:final error):
            if (turnSpan != null && turnSpan.endTime == null) {
              _obs!.endSpan(
                turnSpan,
                extra: {
                  'error': true,
                  'error.type': error.runtimeType.toString(),
                  'error.message': error.toString(),
                },
              );
              turnSpan = null;
            }
            stderr.writeln(error);
            return;

          case AgentNotice(:final message, :final kind):
            // Soft-degradation announcement in --print mode: stderr
            // only, so stdout stays clean for piping the model output.
            final glyph = kind == 'warning' ? '!' : '·';
            stderr.writeln('$glyph $message');

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
        _obs!.endSpan(
          turnSpan,
          extra: {
            'error': true,
            'error.type': e.runtimeType.toString(),
            'error.message': e.toString(),
          },
        );
        turnSpan = null;
      }
      stderr.writeln('Error: $e');
    } finally {
      await agentIter?.cancel();
      await sigintSub.cancel();
      if (turnSpan != null) {
        final obs = _obs!;
        if (turnSpan.endTime == null) {
          obs.endSpan(
            turnSpan,
            extra: {
              'output.value': redactBody(assistantText.toString()),
              'output.length': assistantText.length,
              if (cancelled) 'cancelled': true,
            },
          );
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
      // Tear down the active runtime (cloud sandboxes need this so the
      // user isn't billed for an orphaned sandbox after --print exits).
      if (_runtimeClose != null) {
        try {
          await _runtimeClose();
        } catch (_) {}
      }
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

    final hasEnoughContext =
        (firstAssistantMessage != null &&
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
    _persistRuntimeInfo();
  }

  /// Phase 3: write the active runtime's identity into the session
  /// meta so `/resume`, `glue session …`, and the cleanup sweep can
  /// reason about prior cloud sessions. No-op for host/docker
  /// (sandboxId is empty).
  void _persistRuntimeInfo() {
    final info = _runtimeInfo;
    final store = _sessionManager.currentStore;
    if (info == null || store == null) return;
    if (info.sandboxId.isEmpty) return;
    store.meta
      ..runtimeId = info.runtimeId
      ..sandboxId = info.sandboxId
      ..runtimeBootstrapSha = info.bootstrapSha
      ..runtimeRemoteUrl = info.remoteUrl;
    store.updateMeta();
  }

  /// Resume [session] into the running app. Used by startup paths
  /// (`--resume <id>`, bare `--resume`). The interactive `/resume` command
  /// composes the same primitives directly via [_conversation] —
  /// duplication is deliberate; each call site is self-contained.
  String _resumeSession(SessionMeta session) {
    final result = _sessionManager.resumeSession(
      session: session,
      agent: agent,
    );
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
        'over ${usage.totalCalls} call${usage.totalCalls == 1 ? '' : 's'}',
      );
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
      _bashRunHandle = running;

      final stdoutFuture = running.stdout
          .transform(const SystemEncoding().decoder)
          .join();
      final stderrFuture = running.stderr
          .transform(const SystemEncoding().decoder)
          .join();

      final exitCode = await running.exitCode;
      _bashRunHandle = null;

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
        _obs.endSpan(
          span,
          extra: {
            'process.exit_code': exitCode,
            'process.output_length': stripped.length,
          },
        );
      }
    } catch (e) {
      _bashRunHandle = null;
      _blocks.add(ConversationEntry.error('Bash error: $e'));
      if (span != null && _obs != null && span.endTime == null) {
        _obs.endSpan(
          span,
          extra: {
            'error': true,
            'error.type': e.runtimeType.toString(),
            'error.message': e.toString(),
          },
        );
      }
    }
    _bashSpan = null;
    _mode = AppMode.idle;
    _render();
  }

  void _cancelBash() {
    final span = _bashSpan;
    if (span != null && _obs != null && span.endTime == null) {
      _obs.endSpan(span, extra: {'cancelled': true});
    }
    _bashSpan = null;
    final handle = _bashRunHandle;
    _bashRunHandle = null;
    if (handle != null) handle.kill();
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
          ConversationEntry.system('↳ Job #$id $label ($exitCode): $cmd'),
        );
        _render();
      case JobError(:final id, :final error):
        _blocks.add(ConversationEntry.system('↳ Job #$id error: $error'));
        _render();
    }
  }

  // ── MCP pool events ────────────────────────────────────────────────────

  void _handleMcpEvent(McpPoolEvent event) {
    switch (event) {
      case McpPoolServerConnectedEvent(
        :final serverId,
        :final serverName,
        :final toolNames,
      ):
        final count = toolNames.length;
        _addSystemMessage(
          '↳ MCP connected: $serverId ($serverName, $count tool${count == 1 ? '' : 's'})',
        );
      case McpPoolServerDisconnectedEvent(:final serverId, :final reason):
        _addSystemMessage('↳ MCP disconnected: $serverId — ${reason.name}');
      case McpPoolServerErrorEvent(:final serverId, :final message):
        _addSystemMessage('↳ MCP error ($serverId): $message');
      case McpPoolServerAuthRequiredEvent(
        :final serverId,
        :final reauthCommand,
        :final resourceMetadataUrl,
        :final wwwAuthenticate,
      ):
        _autoOpenAuthFlow(
          serverId: serverId,
          reauthCommand: reauthCommand,
          resourceMetadataUrl: resourceMetadataUrl,
          wwwAuthenticate: wwwAuthenticate,
        );
      case McpPoolToolListChangedEvent(
        :final serverId,
        :final added,
        :final removed,
      ):
        final changes = <String>[
          if (added.isNotEmpty) '+${added.length}',
          if (removed.isNotEmpty) '-${removed.length}',
        ];
        _addSystemMessage(
          '↳ MCP tools changed ($serverId): ${changes.join(' ')}',
        );
    }
    _render();
  }

  // ── MCP auto auth flow ─────────────────────────────────────────────────

  void _autoOpenAuthFlow({
    required String serverId,
    required String reauthCommand,
    required Uri? resourceMetadataUrl,
    required String? wwwAuthenticate,
  }) {
    final config = _config;
    if (config == null) {
      _addSystemMessage(
        '↳ MCP re-auth required ($serverId). Run: $reauthCommand',
      );
      return;
    }

    final snapshot = _mcpPool.server(serverId);
    final spec = snapshot?.spec;
    final baseUrl = switch (spec) {
      McpHttpServerSpec(:final url) => url,
      McpWebSocketServerSpec(:final url) => url,
      _ => null,
    };
    if (baseUrl == null) {
      _addSystemMessage(
        '↳ MCP re-auth required ($serverId). Run: $reauthCommand',
      );
      return;
    }

    final cachedMeta = resourceMetadataUrl ??
        switch (spec) {
          McpHttpServerSpec(:final resourceMetadataUrl) => resourceMetadataUrl,
          McpWebSocketServerSpec(:final resourceMetadataUrl) =>
            resourceMetadataUrl,
          _ => null,
        };

    _addSystemMessage(
      '↳ MCP "$serverId" needs auth — starting OAuth flow.',
    );

    final runner = McpAuthFlowRunner(
      serverId: serverId,
      serverUrl: baseUrl,
      credentials: config.credentials,
      wwwAuthenticate: wwwAuthenticate,
      cachedResourceMetadataUrl: cachedMeta,
      openBrowser: _openMcpAuthBrowser,
    );

    runner.states.listen((state) {
      switch (state) {
        case McpAuthFlowDiscovering():
          _addSystemMessage('  • Discovering OAuth metadata…');
        case McpAuthFlowRegistering():
          _addSystemMessage('  • Registering OAuth client (DCR)…');
        case McpAuthFlowAwaitingCallback(:final authUrl):
          _addSystemMessage('  • Open in browser: $authUrl');
        case McpAuthFlowSuccess(
          :final resourceMetadataUrl,
          :final authorizationServer,
        ):
          _writeBackMcpAuthConfig(
            serverId,
            resourceMetadataUrl,
            authorizationServer,
          );
          _addSystemMessage('  ✓ Signed in to "$serverId". Reconnecting…');
          _mcpPool.reconnect(serverId);
        case McpAuthFlowError(:final message):
          _addSystemMessage('  ✗ OAuth failed for "$serverId": $message');
        case McpAuthFlowCancelled():
          _addSystemMessage('  ✗ OAuth cancelled for "$serverId".');
      }
      _render();
    });

    unawaited(runner.run());
  }

  void _writeBackMcpAuthConfig(
    String serverId,
    Uri? resourceMetadataUrl,
    Uri? authorizationServer,
  ) {
    try {
      final writer = McpConfigWriter(userConfigPath(_environment));
      writer.updateAuth(
        serverId,
        auth: const McpOAuthAuth(),
        resourceMetadataUrl: resourceMetadataUrl,
        authorizationServer: authorizationServer,
      );
    } catch (_) {
      // Non-fatal — tokens are stored, just the config write-back didn't take.
    }
  }

  Future<void> _openMcpAuthBrowser(String url) async {
    try {
      if (Platform.isMacOS) {
        await Process.start('open', [url], mode: ProcessStartMode.detached);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
      } else if (Platform.isWindows) {
        await Process.start('rundll32', [
          'url.dll,FileProtocolHandler',
          url,
        ], mode: ProcessStartMode.detached);
      }
    } catch (_) {
      // URL is already printed via system message.
    }
  }

  // ── Subagent updates ───────────────────────────────────────────────────

  void _handleSubagentUpdate(SubagentUpdate update) {
    final groupKey = '${update.task}:${update.index ?? 0}';
    final group = _subagentGroups.putIfAbsent(groupKey, () {
      final g = SubagentGroup(
        task: update.task,
        index: update.index,
        total: update.total,
      );
      _blocks.add(ConversationEntry.subagentGroup(g));
      return g;
    });

    final prefix = update.index != null
        ? '↳ [${update.index! + 1}/${update.total}]'
        : '↳';

    switch (update.event) {
      case AgentToolCall(:final call):
        group.currentTool = call.name;
        final argsPreview = call.arguments.entries
            .take(2)
            .map((e) => '${e.key}: ${e.value}')
            .join(', ');
        group.entries.add(
          SubagentEntry('$prefix ▶ ${call.name}  $argsPreview'),
        );
        _render();
      case AgentToolResult(:final result):
        final display =
            result.summary ??
            (result.content.length > 80
                ? '${result.content.substring(0, 80)}…'
                : result.content);
        group.entries.add(
          SubagentEntry(
            '$prefix ✓ ${display.replaceAll('\n', ' ')}',
            rawContent: result.summary != null || result.content.length > 80
                ? result.content
                : null,
          ),
        );
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
      case AgentNotice(:final message, :final kind):
        // Subagent emitted a notice (e.g. its own model lacks tools and
        // it's running chat-only). Surface inside the subagent group
        // fold so the parent transcript shows the soft degradation.
        final glyph = kind == 'warning' ? '!' : '·';
        group.entries.add(SubagentEntry('$prefix $glyph $message'));
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
