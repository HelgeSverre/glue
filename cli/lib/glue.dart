/// Glue — the coding agent that holds it all together.
library;

export 'src/app.dart' show App, AppMode;
export 'src/terminal/terminal.dart'
    show Terminal, TerminalEvent, KeyEvent, CharEvent, ResizeEvent, MouseEvent, Key, AnsiStyle;
export 'src/terminal/layout.dart' show Layout;
export 'src/input/line_editor.dart' show LineEditor, InputAction;
export 'src/agent/agent_core.dart'
    show AgentCore, LlmClient, LlmChunk, TextDelta, ToolCallDelta, UsageInfo, ToolCall, ToolResult, Message;
export 'src/agent/tools.dart' show Tool, ToolParameter, ReadFileTool, WriteFileTool, BashTool, GrepTool, ListDirectoryTool;
export 'src/config/glue_config.dart' show GlueConfig, LlmProvider, AgentProfile, ConfigError;
export 'src/llm/llm_factory.dart' show LlmClientFactory;
export 'src/agent/agent_runner.dart' show AgentRunner, ToolApprovalPolicy;
export 'src/agent/agent_manager.dart' show AgentManager;
export 'src/agent/prompts.dart' show Prompts;
export 'src/rendering/ansi_utils.dart' show stripAnsi, visibleLength, ansiTruncate, ansiWrap;
export 'src/rendering/block_renderer.dart' show BlockRenderer;
export 'src/rendering/markdown_renderer.dart' show MarkdownRenderer;
export 'src/commands/slash_commands.dart' show SlashCommand, SlashCommandRegistry;
export 'src/ui/modal.dart' show ConfirmModal, ModalChoice;
export 'src/storage/glue_home.dart' show GlueHome;
export 'src/storage/session_store.dart' show SessionStore, SessionMeta;
export 'src/storage/debug_logger.dart' show DebugLogger;
export 'src/storage/config_store.dart' show ConfigStore;
export 'src/input/file_expander.dart' show expandFileRefs, extractFileRefs;
export 'src/ui/at_file_hint.dart' show AtFileHint;
