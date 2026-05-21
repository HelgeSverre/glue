import 'package:glue_harness/glue_harness.dart';
import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/input/text_area_editor.dart';
import 'package:glue/src/services/approval_state.dart';
import 'package:glue/src/services/conversation_view.dart';
import 'package:glue/src/services/lifecycle.dart';
import 'package:glue/src/ui/dock_manager.dart';
import 'package:glue/src/ui/model_panel_formatter.dart' show CatalogRow;
import 'package:glue/src/ui/modal_surface.dart';

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
    required this.editor,
    required this.mcpPool,
    required this.autoApprovedTools,
    required this.ensureSession,
    required this.backfillTitle,
    required this.switchModel,
    // Services
    required this.conversation,
    required this.approval,
    required this.lifecycle,
    required this.panels,
    // Self-reference for /help-style enumeration
    required Iterable<SlashCommand> Function() commandsGetter,
  }) : _config = configGetter,
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

  /// The textarea backing the input prompt. Commands that seed the prompt
  /// (e.g., `/history` after a fork) write to this directly.
  final TextAreaEditor editor;

  /// Pool of connected MCP servers. Always present (empty when no
  /// servers configured). Used by `/mcp …` slash commands.
  final McpClientPool mcpPool;

  /// Live reference to the auto-approved tool name set. Contents may be
  /// mutated by approval flows; readers see the current set on each access.
  final Set<String> autoApprovedTools;

  /// Ensures the current session has a backing store (creates one if needed).
  /// Commands that log events or persist state should call this before
  /// touching `session.logEvent` / `session.currentStore`.
  final void Function() ensureSession;

  /// Asynchronously generate a title for the current session given an early
  /// user message. Used by `/resume` to backfill titles for sessions that
  /// were saved before titling existed.
  final void Function(String firstUserMessage) backfillTitle;

  /// Apply a model switch: handles the Ollama pull-confirm flow (interactive
  /// `ConfirmModal`) when needed and otherwise mutates `agent.llm`,
  /// `config.activeModel`, the cached model id, and persists the active
  /// model on the session store. Returns an inline result message for
  /// synchronous switches; returns `''` when an async confirm is pending.
  ///
  /// Temporary seam: the Ollama confirm flow couples to App-mode state
  /// (`_mode = AppMode.confirming`, `_activeModal`). Decomposing it requires
  /// a larger design pass — left as a callback for now.
  final String Function(CatalogRow row) switchModel;

  final ConversationView conversation;
  final ApprovalState approval;
  final Lifecycle lifecycle;

  /// The existing TUI panel host. Today this still carries domain-specific
  /// openers (`openHelp`, `openModel`, etc.). Long-term plan is to slim it
  /// down to generic primitives and move panel-assembly into commands.
  final ModalSurface panels;

  final GlueConfig? Function() _config;
  final LlmClientFactory? Function() _llmFactory;
  final AgentCore Function() _agent;
  final String Function() _cwd;
  final String Function() _modelId;
  final bool Function() _isIdle;
  final Iterable<SlashCommand> Function() _commands;
}
