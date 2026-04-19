/// A terminal-native coding agent that streams LLM responses, executes tools,
/// and renders everything in a responsive TUI.
///
/// The main entry point is [App], which wires together terminal I/O, the
/// agent loop, and rendering. Key concepts:
///
/// - **Agent loop**: [AgentCore] runs the LLM ↔ [Tool] ReAct loop, emitting
///   `AgentEvent`s. [AgentRunner] drives it headlessly; [AgentManager]
///   orchestrates subagent spawning.
/// - **LLM providers**: [LlmClient] is implemented by provider-specific
///   clients for Anthropic, OpenAI, and Ollama. Use [LlmClientFactory] to
///   create them from [GlueConfig].
/// - **Terminal**: [Terminal] handles raw I/O and ANSI parsing; [Layout]
///   divides the screen into scroll regions; [BlockRenderer] and
///   [MarkdownRenderer] produce styled output.
/// - **Configuration**: [GlueConfig] resolves settings from CLI args → env
///   vars → `~/.glue/config.yaml` → defaults. [ModelRegistry] catalogs
///   supported models.
/// - **Shell execution**: [CommandExecutor] abstracts host ([HostExecutor])
///   and Docker ([DockerExecutor]) command execution.
/// - **Observability**: [Observability] traces spans and routes them to
///   pluggable [ObservabilitySink]s (OpenTelemetry, Langfuse, file).
library;

export 'src/app.dart' show App, AppMode;
export 'src/terminal/terminal.dart'
    show
        Terminal,
        TerminalEvent,
        KeyEvent,
        CharEvent,
        ResizeEvent,
        MouseEvent,
        PasteEvent,
        Key,
        AnsiStyle;
export 'src/terminal/layout.dart' show Layout;
export 'src/input/line_editor.dart' show LineEditor, InputAction;
export 'src/input/text_area_editor.dart' show TextAreaEditor;
export 'src/agent/agent_core.dart'
    show
        AgentCore,
        LlmClient,
        LlmChunk,
        TextDelta,
        ToolCallComplete,
        UsageInfo,
        ToolCall,
        ToolResult,
        Message;
export 'src/agent/content_part.dart' show ContentPart, TextPart, ImagePart;
export 'src/agent/tools.dart'
    show
        Tool,
        ToolTrust,
        ForwardingTool,
        ToolParameter,
        ReadFileTool,
        WriteFileTool,
        EditFileTool,
        BashTool,
        GrepTool,
        ListDirectoryTool;
export 'src/config/constants.dart' show AppConstants;
export 'src/config/glue_config.dart'
    show GlueConfig, LlmProvider, AgentProfile, ConfigError, splitPathList;
export 'src/config/approval_mode.dart' show ApprovalMode, ApprovalModeExt;
export 'src/config/model_registry.dart'
    show ModelRegistry, ModelEntry, ModelCapability, CostTier, SpeedTier;
export 'src/llm/llm_factory.dart' show LlmClientFactory;
export 'src/agent/agent_runner.dart' show AgentRunner, ToolApprovalPolicy;
export 'src/agent/agent_manager.dart' show AgentManager;
export 'src/agent/prompts.dart' show Prompts;
export 'src/rendering/ansi_utils.dart'
    show
        osc8Link,
        stripAnsi,
        visibleLength,
        ansiTruncate,
        ansiWrap,
        wrapIndented,
        charWidth;
export 'src/rendering/block_renderer.dart' show BlockRenderer;
export 'src/rendering/markdown_renderer.dart' show MarkdownRenderer;
export 'src/commands/slash_commands.dart'
    show SlashCommand, SlashCommandRegistry;
export 'src/commands/builtin_commands.dart' show BuiltinCommands;
export 'src/ui/modal.dart' show ConfirmModal, ModalChoice;
export 'src/ui/box.dart' show Box;
export 'src/ui/panel_modal.dart'
    show
        PanelModal,
        PanelStyle,
        PanelOverlay,
        BarrierStyle,
        PanelSize,
        PanelFixed,
        PanelFluid;
export 'src/ui/panel_controller.dart' show PanelController, HistoryPanelEntry;
export 'src/ui/split_panel_modal.dart' show SplitPanelModal;
export 'src/skills/skill_parser.dart'
    show SkillMeta, SkillSource, SkillParseError;
export 'src/skills/skill_registry.dart' show SkillRegistry;
export 'src/skills/skill_runtime.dart' show SkillRuntime, SkillPathsProvider;
export 'src/skills/skill_tool.dart' show SkillTool;
export 'src/core/environment.dart' show Environment;
export 'src/core/service_locator.dart' show ServiceLocator, AppServices;
export 'src/orchestrator/permission_gate.dart'
    show PermissionGate, PermissionDecision;
export 'src/session/session_manager.dart'
    show
        SessionManager,
        SessionReplay,
        SessionReplayEntry,
        SessionReplayKind,
        SessionResumeResult,
        SessionForkResult;
export 'src/storage/session_store.dart' show SessionStore, SessionMeta;
export 'src/observability/observability.dart'
    show Observability, ObservabilitySink, ObservabilitySpan;
export 'src/observability/debug_controller.dart' show DebugController;
export 'src/observability/file_sink.dart' show FileSink;
export 'src/observability/observability_config.dart' show ObservabilityConfig;
export 'src/storage/config_store.dart' show ConfigStore;
export 'src/input/file_expander.dart' show expandFileRefs, extractFileRefs;
export 'src/ui/at_file_hint.dart' show AtFileHint;
export 'src/ui/autocomplete_overlay.dart'
    show AutocompleteOverlay, AcceptResult;
export 'src/shell/command_executor.dart'
    show CommandExecutor, CaptureResult, RunningCommand;
export 'src/shell/docker_config.dart' show DockerConfig, MountEntry, MountMode;
export 'src/shell/docker_executor.dart' show DockerExecutor;
export 'src/shell/executor_factory.dart' show ExecutorFactory;
export 'src/shell/host_executor.dart' show HostExecutor;
export 'src/shell/shell_config.dart' show ShellConfig, ShellMode;
export 'src/storage/session_state.dart' show SessionState;
export 'src/shell/line_ring_buffer.dart' show LineRingBuffer;
export 'src/shell/shell_job_manager.dart'
    show
        ShellJobManager,
        ShellJob,
        JobStatus,
        JobEvent,
        JobStarted,
        JobExited,
        JobError;
