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

// Surface — owned by this (cli) package.
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
export 'src/input/file_expander.dart' show expandFileRefs, extractFileRefs;
export 'src/rendering/ansi_utils.dart'
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
export 'src/rendering/block_renderer.dart' show BlockRenderer;
export 'src/rendering/markdown_renderer.dart' show MarkdownRenderer;
export 'src/commands/slash_commands.dart'
    show
        SlashArgCandidate,
        SlashArgCompleter,
        SlashCommand,
        SlashCommandRegistry;
export 'src/commands/builtin_commands.dart' show BuiltinCommands;
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
export 'src/ui/at_file_hint.dart' show AtFileHint;
export 'src/ui/autocomplete_overlay.dart'
    show AutocompleteOverlay, AcceptResult;

// Core data types — re-exported from glue_core so consumers of the cli
// barrel can keep their existing import path.
export 'package:glue_core/glue_core.dart'
    show
        AppConstants,
        AuthKind,
        AuthSpec,
        Capability,
        ContentPart,
        ImagePart,
        LlmChunk,
        LlmClient,
        Message,
        ModelCatalog,
        ModelDef,
        ModelRef,
        ModelRefParseException,
        ProviderDef,
        TextDelta,
        TextPart,
        ToolCall,
        ToolCallComplete,
        UsageInfo;

// Strategy implementations.
export 'package:glue_strategies/glue_strategies.dart'
    show
        AdapterRegistry,
        AnthropicAdapter,
        CaptureResult,
        CommandExecutor,
        CompatibilityProfile,
        CredentialRef,
        CredentialStore,
        DiscoveredModel,
        DockerConfig,
        DockerExecutor,
        EnvCredential,
        ExecutorFactory,
        HostExecutor,
        InlineCredential,
        LineRingBuffer,
        MountEntry,
        MountMode,
        NoCredential,
        OpenAiCompatibleAdapter,
        ProviderAdapter,
        ProviderHealth,
        ResolvedModel,
        ResolvedProvider,
        RunningCommand,
        ShellConfig,
        ShellMode,
        StoredCredential;

// Harness orchestration.
export 'package:glue_harness/glue_harness.dart'
    show
        AgentCore,
        AgentManager,
        AgentRunner,
        AppServices,
        BuildInfo,
        CatalogSourceConfig,
        ConfigError,
        ConfigStore,
        DebugController,
        EditFileTool,
        Environment,
        FileSink,
        ForwardingTool,
        GlueConfig,
        JobError,
        JobEvent,
        JobExited,
        JobStarted,
        JobStatus,
        LlmClientFactory,
        Observability,
        ObservabilityConfig,
        ObservabilitySink,
        ObservabilitySpan,
        PermissionDecision,
        PermissionGate,
        Prompts,
        ReadFileTool,
        ServiceLocator,
        SessionForkResult,
        SessionManager,
        SessionMeta,
        SessionReplay,
        SessionReplayEntry,
        SessionReplayKind,
        SessionResumeResult,
        SessionState,
        SessionStore,
        ShellJob,
        ShellJobManager,
        SkillMeta,
        SkillParseError,
        SkillPathsProvider,
        SkillRegistry,
        SkillRuntime,
        SkillSource,
        SkillTool,
        Tool,
        ToolApprovalPolicy,
        ToolParameter,
        ToolResult,
        ToolTrust,
        ApprovalMode,
        ApprovalModeExt,
        BashTool,
        GrepTool,
        ListDirectoryTool,
        WriteFileTool,
        bundledCatalog,
        buildConfigTemplate,
        buildWhereReport,
        loadCatalog,
        openInFileManager,
        parseCatalogYaml,
        CatalogParseException,
        splitPathList;
