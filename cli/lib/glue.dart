/// Glue — the coding agent that holds it all together.
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
        Key,
        AnsiStyle;
export 'src/terminal/layout.dart' show Layout;
export 'src/input/line_editor.dart' show LineEditor, InputAction;
export 'src/agent/agent_core.dart'
    show
        AgentCore,
        LlmClient,
        LlmChunk,
        TextDelta,
        ToolCallDelta,
        UsageInfo,
        ToolCall,
        ToolResult,
        Message;
export 'src/agent/tools.dart'
    show
        Tool,
        ToolParameter,
        ReadFileTool,
        WriteFileTool,
        EditFileTool,
        BashTool,
        GrepTool,
        ListDirectoryTool;
export 'src/config/glue_config.dart'
    show GlueConfig, LlmProvider, AgentProfile, ConfigError;
export 'src/config/model_registry.dart'
    show ModelRegistry, ModelEntry, ModelCapability, CostTier, SpeedTier;
export 'src/llm/llm_factory.dart' show LlmClientFactory;
export 'src/agent/agent_runner.dart' show AgentRunner, ToolApprovalPolicy;
export 'src/agent/agent_manager.dart' show AgentManager;
export 'src/agent/prompts.dart' show Prompts;
export 'src/rendering/ansi_utils.dart'
    show stripAnsi, visibleLength, ansiTruncate, ansiWrap;
export 'src/rendering/block_renderer.dart' show BlockRenderer;
export 'src/rendering/markdown_renderer.dart' show MarkdownRenderer;
export 'src/commands/slash_commands.dart'
    show SlashCommand, SlashCommandRegistry;
export 'src/ui/modal.dart' show ConfirmModal, ModalChoice;
export 'src/ui/panel_modal.dart'
    show
        PanelModal,
        PanelStyle,
        BarrierStyle,
        PanelSize,
        PanelFixed,
        PanelFluid;
export 'src/ui/split_panel_modal.dart' show SplitPanelModal;
export 'src/ui/panel_modal.dart' show PanelOverlay;
export 'src/skills/skill_parser.dart'
    show SkillMeta, SkillSource, SkillParseError;
export 'src/skills/skill_registry.dart' show SkillRegistry;
export 'src/skills/skill_tool.dart' show SkillTool;
export 'src/storage/glue_home.dart' show GlueHome;
export 'src/storage/session_store.dart' show SessionStore, SessionMeta;
export 'src/observability/observability.dart' show Observability, ObservabilitySink, ObservabilitySpan;
export 'src/observability/debug_controller.dart' show DebugController;
export 'src/observability/file_sink.dart' show FileSink;
export 'src/observability/otel_sink.dart' show OtelSink;
export 'src/observability/langfuse_sink.dart' show LangfuseSink;
export 'src/observability/logging_http_client.dart' show LoggingHttpClient;
export 'src/observability/observed_llm_client.dart' show ObservedLlmClient;
export 'src/observability/observed_tool.dart' show ObservedTool, wrapToolsWithObservability;
export 'src/observability/observability_config.dart' show ObservabilityConfig, LangfuseConfig, TelemetryProvider;
export 'src/storage/config_store.dart' show ConfigStore;
export 'src/input/file_expander.dart' show expandFileRefs, extractFileRefs;
export 'src/ui/at_file_hint.dart' show AtFileHint;
export 'src/shell/command_executor.dart'
    show CommandExecutor, CaptureResult, RunningCommand;
export 'src/shell/docker_config.dart'
    show DockerConfig, MountEntry, MountMode;
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
