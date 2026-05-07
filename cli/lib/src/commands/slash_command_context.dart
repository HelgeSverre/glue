import 'package:glue_harness/glue_harness.dart';

import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/services/approval_state.dart';
import 'package:glue/src/services/conversation_view.dart';
import 'package:glue/src/services/lifecycle.dart';
import 'package:glue/src/ui/dock_manager.dart';
import 'package:glue/src/ui/model_panel_formatter.dart' show CatalogRow;
import 'package:glue/src/ui/panel_controller.dart';

/// Single dependency surface every slash command receives.
///
/// Exposes runtime objects (live readers for things that may be `null` or
/// `late` on `App` at construction time) and the small set of generic
/// services the command system relies on. Commands take only this; no
/// bespoke per-command callbacks.
class SlashCommandContext {
  SlashCommandContext({
    // Runtime — live readers
    required GlueConfig? Function() configGetter,
    required LlmClientFactory? Function() llmFactoryGetter,
    required AgentCore Function() agentGetter,
    required String Function() cwdGetter,
    required String Function() modelIdGetter,
    required bool Function() isIdleGetter,
    // Runtime — stable
    required this.environment,
    required this.session,
    required this.skills,
    required this.debug,
    required this.dockManager,
    required this.autoApprovedTools,
    required this.ensureSession,
    required this.resumeFromMeta,
    required this.forkSession,
    required this.switchModel,
    // Services
    required this.conversation,
    required this.approval,
    required this.lifecycle,
    required this.panels,
    // Self-reference for /help-style enumeration
    required Iterable<SlashCommand> Function() commandsGetter,
  })  : _config = configGetter,
        _llmFactory = llmFactoryGetter,
        _agent = agentGetter,
        _cwd = cwdGetter,
        _modelId = modelIdGetter,
        _isIdle = isIdleGetter,
        _commands = commandsGetter;

  /// Currently-active config, if any. May be `null` until startup completes.
  GlueConfig? get config => _config();

  /// Live LLM client factory. May be `null` if no provider is configured.
  LlmClientFactory? get llmFactory => _llmFactory();

  /// Live agent core (always present once the app is running).
  AgentCore get agent => _agent();

  /// Current working directory.
  String get cwd => _cwd();

  /// Live identifier of the active model. Mutates when `/model` switches.
  String get modelId => _modelId();

  /// True when the agent loop is idle (no streaming, tool, or bash command in
  /// flight). Commands that mutate session state should gate on this.
  bool get isIdle => _isIdle();

  /// All registered slash commands. Used by `/help` to enumerate.
  Iterable<SlashCommand> get commands => _commands();

  final Environment environment;
  final SessionManager session;
  final SkillRuntime skills;
  final DebugController? debug;
  final DockManager dockManager;

  /// Live reference to the auto-approved tool name set. Contents may be
  /// mutated by approval flows; readers see the current set on each access.
  final Set<String> autoApprovedTools;

  /// Ensures the current session has a backing store (creates one if needed).
  /// Commands that log events or persist state should call this before
  /// touching `session.logEvent` / `session.currentStore`.
  final void Function() ensureSession;

  /// Resumes a saved session into the running app. Backed by App-internal
  /// orchestration that clears UI state, replays the transcript, and
  /// triggers title backfill. Returns the user-visible result message.
  ///
  /// This is a temporary seam: the session-mutation half lives on
  /// `SessionManager.resumeSession` already; once `ConversationView`
  /// grows `resetForReplay()` and `appendReplayEntries()`, the App-side
  /// part can be inlined into the resume command itself and this callback
  /// removed.
  final String Function(SessionMeta) resumeFromMeta;

  /// Forks the current session at the user message at [userMessageIndex].
  /// Backed by App-internal orchestration that clears the transcript,
  /// replays up to the fork point, and seeds the editor with [messageText].
  ///
  /// Same temporary-seam status as [resumeFromMeta].
  final void Function(int userMessageIndex, String messageText) forkSession;

  /// Apply a model switch: handles the Ollama pull-confirm flow (interactive
  /// `ConfirmModal`) when needed and otherwise mutates `agent.llm`,
  /// `config.activeModel`, the cached model id, and persists the active
  /// model on the session store. Returns an inline result message for
  /// synchronous switches; returns `''` when an async confirm is pending.
  ///
  /// Same temporary-seam status as [resumeFromMeta] / [forkSession].
  final String Function(CatalogRow row) switchModel;

  final ConversationView conversation;
  final ApprovalState approval;
  final Lifecycle lifecycle;

  /// The existing TUI panel host. Today this still carries domain-specific
  /// openers (`openHelp`, `openModel`, etc.). Long-term plan is to slim it
  /// down to generic primitives and move panel-assembly into commands; see
  /// `~/.claude/plans/investigate-how-recap-feature-radiant-snowglobe.md`.
  final PanelController panels;

  final GlueConfig? Function() _config;
  final LlmClientFactory? Function() _llmFactory;
  final AgentCore Function() _agent;
  final String Function() _cwd;
  final String Function() _modelId;
  final bool Function() _isIdle;
  final Iterable<SlashCommand> Function() _commands;
}
