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
export 'src/runtime/app_launch_options.dart' show AppLaunchOptions;
export 'src/runtime/app_shell.dart' show AppShell;
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
        Message;
export 'src/agent/content_part.dart' show ContentPart, TextPart, ImagePart;
export 'src/agent/tools.dart'
    show
        Tool,
        ToolTrust,
        ToolResult,
        ForwardingTool,
        ToolParameter,
        ReadFileTool,
        WriteFileTool,
        EditFileTool,
        BashTool,
        GrepTool,
        ListDirectoryTool;
export 'src/config/build_info.dart' show BuildInfo;
export 'src/config/constants.dart' show AppConstants;
export 'src/config/glue_config.dart'
    show GlueConfig, CatalogSourceConfig, ConfigError, splitPathList;
export 'src/config/approval_mode.dart' show ApprovalMode, ApprovalModeExt;
export 'src/catalog/model_catalog.dart'
    show ModelCatalog, ProviderDef, ModelDef, AuthSpec, AuthKind, Capability;
export 'src/catalog/model_ref.dart' show ModelRef, ModelRefParseException;
export 'src/catalog/catalog_loader.dart' show loadCatalog;
export 'src/catalog/catalog_parser.dart'
    show parseCatalogYaml, CatalogParseException;
export 'src/catalog/models_generated.dart' show bundledCatalog;
export 'src/credentials/credential_ref.dart'
    show
        CredentialRef,
        EnvCredential,
        StoredCredential,
        InlineCredential,
        NoCredential;
export 'src/credentials/credential_store.dart' show CredentialStore;
export 'src/providers/provider_adapter.dart'
    show ProviderAdapter, AdapterRegistry, ProviderHealth, DiscoveredModel;
export 'src/providers/resolved.dart' show ResolvedProvider, ResolvedModel;
export 'src/providers/compatibility_profile.dart' show CompatibilityProfile;
export 'src/providers/anthropic_adapter.dart' show AnthropicAdapter;
export 'src/providers/openai_compatible_adapter.dart'
    show OpenAiCompatibleAdapter;
export 'src/providers/llm_client_factory.dart' show LlmClientFactory;
export 'src/agent/agent_runner.dart' show AgentRunner, ToolApprovalPolicy;
export 'src/agent/agent_manager.dart' show AgentManager;
export 'src/agent/prompts.dart' show Prompts;
export 'src/session/title_generator.dart' show TitleGenerator;
export 'src/ui/rendering/ansi_utils.dart'
    show
        osc8Link,
        osc8FileLink,
        linkifyUrls,
        stripAnsi,
        visibleLength,
        ansiTruncate,
        ansiWrap,
        wrapIndented,
        charWidth;
export 'src/ui/rendering/block_renderer.dart' show BlockRenderer;
export 'src/ui/rendering/markdown_renderer.dart' show MarkdownRenderer;
export 'src/commands/slash_commands.dart'
    show
        SlashArgCandidate,
        SlashArgCompleter,
        SlashCommand,
        SlashCommandRegistry;
export 'src/commands/builtin_commands.dart' show BuiltinCommands;
export 'src/ui/components/box.dart' show Box;
export 'src/ui/components/modal.dart' show ConfirmModal, ModalChoice;
export 'src/ui/components/panel.dart'
    show
        AbstractPanel,
        Panel,
        SelectPanel,
        SplitPanel,
        PanelStyle,
        BarrierStyle,
        PanelSize,
        PanelFixed,
        PanelFluid;
export 'src/ui/services/panels.dart' show Panels;
export 'src/ui/services/docks.dart' show Docks;
export 'src/runtime/controllers/provider_controller.dart'
    show ProviderAction, providerActionsFor;
export 'src/runtime/controllers/session_controller.dart' show HistoryPanelEntry;
export 'src/skills/skill_parser.dart'
    show SkillMeta, SkillSource, SkillParseError;
export 'src/skills/skill_registry.dart' show SkillRegistry;
export 'src/skills/skill_runtime.dart' show SkillRuntime, SkillPathsProvider;
export 'src/skills/skill_tool.dart' show SkillTool;
export 'src/core/environment.dart' show Environment;
export 'src/core/path_opener.dart' show openInFileManager;
export 'src/core/service_locator.dart' show ServiceLocator, AppServices;
export 'src/core/where_report.dart' show buildWhereReport;
export 'src/config/config_template.dart' show buildConfigTemplate;
export 'src/commands/config_command.dart'
    show
        ConfigInitResult,
        ConfigInitStatus,
        ConfigValidationResult,
        initUserConfig,
        userConfigPath,
        validateUserConfig;
export 'src/doctor/doctor.dart'
    show
        DoctorFinding,
        DoctorReport,
        DoctorSeverity,
        renderDoctorReport,
        runDoctor;
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
export 'src/input/at_file_hint.dart' show AtFileHint;
export 'src/ui/components/overlays.dart' show AutocompleteOverlay, AcceptResult;
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
