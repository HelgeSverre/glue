import 'dart:async';
import 'dart:io';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/providers/llm_client_factory.dart';
import 'package:glue/src/runtime/services/config.dart';
import 'package:glue/src/runtime/transcript.dart';
import 'package:glue/src/session/session_manager.dart';
import 'package:glue/src/session/title_generator.dart';
import 'package:glue/src/storage/session_store.dart';
import 'package:glue/src/utils.dart';

/// Feature-facing handle to the current session and all session-lifecycle
/// behaviour: resume, fork, replay, title generation / reevaluation, and
/// the cross-turn title-state bookkeeping that used to live in a separate
/// `SessionTitleStateController`.
///
/// Disk-level persistence stays in [SessionManager] / `session_store.dart`
/// underneath — this service is the controller-facing facade plus
/// app-level behaviour that the title flow needs (reading `agent.conversation`,
/// mutating the [Transcript] on resume).
class Session {
  Session({
    required this.manager,
    required Agent agent,
    required Transcript transcript,
    required Config config,
    required Environment environment,
    required String Function() modelIdProvider,
    required void Function(String) installDraft,
    LlmClientFactory? llmFactory,
  })  : _agent = agent,
        _transcript = transcript,
        _config = config,
        _environment = environment,
        _modelIdProvider = modelIdProvider,
        _installDraft = installDraft,
        _llmFactory = llmFactory;

  final SessionManager manager;
  final Agent _agent;
  final Transcript _transcript;
  final Config _config;
  final Environment _environment;
  final String Function() _modelIdProvider;
  final void Function(String) _installDraft;
  final LlmClientFactory? _llmFactory;

  // ── Title state (absorbed from SessionTitleStateController) ──────────
  bool _titleInitialRequested = false;
  bool _titleReevalRequested = false;
  bool _titleManuallyOverridden = false;

  // ── Current-session accessors ────────────────────────────────────────

  /// Metadata for the currently open session, or null if none yet.
  SessionMeta? get currentMeta => manager.currentStore?.meta;

  /// Id of the currently open session, or null if none.
  String? get currentId => manager.currentSessionId;

  /// The disk-backed store for the current session, or null.
  SessionStore? get currentStore => manager.currentStore;

  /// All saved sessions, most-recent-first.
  List<SessionMeta> list() => manager.listSessions();

  // ── Lifecycle operations ─────────────────────────────────────────────

  /// Create the session store if not already created. Uses the current
  /// config's active model or the runtime [modelIdProvider] as fallback.
  void ensureStore() {
    manager.ensureSessionStore(
      cwd: _environment.cwd,
      modelRef: _config.current?.activeModel.toString() ?? _modelIdProvider(),
    );
  }

  /// Append an event to the current session's on-disk log.
  void logEvent(String type, Map<String, dynamic> data) =>
      manager.logEvent(type, data);

  /// Flush and close the current session's on-disk store.
  Future<void> closeCurrent() => manager.closeCurrent();

  /// Update the model-ref stored on the current session's metadata.
  void updateModel(String modelRef) =>
      manager.updateSessionModel(modelRef: modelRef);

  /// Rename the current session's title. Marks the title as manually
  /// overridden so automatic re-evaluation stops touching it.
  Future<void> rename(String title) async {
    markManualRename();
    await manager.renameTitle(title);
  }

  /// Flag the current title as user-supplied; blocks initial + re-eval
  /// generation so we don't overwrite the user's choice.
  void markManualRename() {
    _titleInitialRequested = true;
    _titleReevalRequested = true;
    _titleManuallyOverridden = true;
  }

  /// Resume a previously-saved session into the in-memory agent and
  /// transcript. Returns the system-visible status string to display.
  ///
  /// Clears the transcript (caller is expected to trigger a render
  /// afterwards), replays persisted entries into it, and kicks off
  /// initial title generation if the resumed session had no title yet.
  String resume(SessionMeta meta) {
    final result = manager.resumeSession(session: meta, agent: _agent);
    _transcript.blocks.clear();
    _transcript.toolUi.clear();
    _transcript.streamingText = '';
    _transcript.subagentGroups.clear();
    _transcript.outputLineGroups.clear();
    _applyResumedTitleState(meta);

    _transcript.blocks.add(ConversationEntry.system(
      'Resuming session ${meta.id} '
      '(${meta.modelRef}, ${meta.startTime.timeAgo})',
    ));

    if (!result.hasConversation) {
      return 'Session ${meta.id} has no conversation data.';
    }

    _appendReplayEntries(result.replay.entries);

    final firstUserMessage = result.replay.firstUserMessage;
    if (_shouldGenerateInitialTitle &&
        firstUserMessage != null &&
        firstUserMessage.isNotEmpty) {
      _titleInitialRequested = true;
      _generateTitle(firstUserMessage);
    }

    return result.message;
  }

  /// Fork the current conversation at [userMessageIndex]. Truncates the
  /// transcript to the chosen message, replays the surviving entries,
  /// and installs the saved draft text into the caller's editor via the
  /// [installDraft] callback provided at construction.
  ///
  /// Returns `true` if the fork succeeded and the transcript was
  /// mutated — caller should schedule a render. Returns `false` if the
  /// underlying session store refused the fork (no-op).
  bool fork(int userMessageIndex, String messageText) {
    final result = manager.forkSession(
      userMessageIndex: userMessageIndex,
      messageText: messageText,
      agent: _agent,
    );
    if (result == null) return false;

    _transcript.blocks.clear();
    _transcript.blocks.add(ConversationEntry.system(result.message));
    _appendReplayEntries(result.replay.entries);
    _installDraft(result.draftText);
    return true;
  }

  /// Kick off an initial title generation from the first user message in
  /// a new session, if the session doesn't already have a title. No-op
  /// once initial titling has already happened or the user manually
  /// renamed. Called once per session from the user-submit path.
  void maybeGenerateInitialTitle(String userMessage) {
    if (!_shouldGenerateInitialTitle) return;
    _titleInitialRequested = true;
    _generateTitle(userMessage);
  }

  /// Called by `Turn` after every `AgentDone`. Decides whether to run a
  /// title re-evaluation against the current conversation and kicks it
  /// off in the background when appropriate.
  void onTurnComplete() {
    if (_blocksTitleReevaluation) return;
    final meta = manager.currentStore?.meta;
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
    for (final message in _agent.conversation) {
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
    _titleReevalRequested = true;
    final generator = TitleGenerator(llmClient: llmClient);
    unawaited(manager.reevaluateTitle(
      context: TitleContext(
        firstUserMessage: firstUserMessage,
        latestUserMessage: latestUserMessage,
        firstAssistantMessage: firstAssistantMessage,
        latestAssistantMessage: latestAssistantMessage,
        toolNames: toolNames,
        cwdBasename: _environment.cwd.split(Platform.pathSeparator).last,
      ),
      generate: generator.generateFromContext,
    ));
  }

  // ── Internals ────────────────────────────────────────────────────────

  bool get _shouldGenerateInitialTitle =>
      !_titleInitialRequested && !_titleManuallyOverridden;

  bool get _blocksTitleReevaluation =>
      _titleReevalRequested || _titleManuallyOverridden;

  void _applyResumedTitleState(SessionMeta meta) {
    _titleInitialRequested = meta.title != null;
    _titleReevalRequested = meta.titleState == SessionTitleState.stable ||
        meta.titleGenerationCount >= 2;
    _titleManuallyOverridden = meta.titleSource == SessionTitleSource.user;
  }

  void _generateTitle(String userMessage) {
    final llmClient = _createTitleLlmClient();
    if (llmClient == null) return;

    final generator = TitleGenerator(llmClient: llmClient);
    unawaited(manager.generateTitle(
      userMessage: userMessage,
      generate: generator.generate,
    ));
  }

  /// Build an [LlmClient] for title generation against the configured
  /// small model (falling back to the active model). Returns null when
  /// title generation is disabled in config or credentials are missing.
  LlmClient? _createTitleLlmClient() {
    final cfg = _config.current;
    final factory = _llmFactory;
    if (cfg == null || factory == null) return null;

    if (!cfg.titleGenerationEnabled) {
      if (cfg.observability.debug) {
        stderr.writeln('[debug] title generation disabled; skipping');
      }
      return null;
    }

    final ref = cfg.smallModel ?? cfg.activeModel;
    try {
      return factory.createFor(ref, systemPrompt: TitleGenerator.systemPrompt);
    } on ConfigError {
      // No adapter or missing credentials for the small model — skip titling.
      return null;
    }
  }

  void _appendReplayEntries(List<SessionReplayEntry> entries) {
    for (final entry in entries) {
      switch (entry.kind) {
        case SessionReplayKind.user:
          _transcript.blocks.add(ConversationEntry.user(entry.text));
        case SessionReplayKind.assistant:
          _transcript.blocks.add(ConversationEntry.assistant(entry.text));
        case SessionReplayKind.toolCall:
          _transcript.blocks.add(ConversationEntry.toolCall(
            entry.toolName ?? entry.text,
            entry.toolArguments ?? const <String, dynamic>{},
          ));
        case SessionReplayKind.toolResult:
          _transcript.blocks.add(ConversationEntry.toolResult(entry.text));
      }
    }
  }
}
