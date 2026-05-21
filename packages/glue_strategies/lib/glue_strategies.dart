/// Strategy implementations consumed by Glue's harness.
///
/// **Layering:** strategies sit above `glue_core` (pure data) and below
/// the harness (`cli/lib/src/`). They wrap external services — LLM
/// providers, shell executors, credential stores, web fetch/browser/search
/// — behind interfaces that the harness composes through factories.
///
/// See `docs/plans/2026-04-29-harness-layers.md`.
library;

export 'package:glue_strategies/src/credentials/credential_ref.dart';
export 'package:glue_strategies/src/credentials/credential_store.dart';
export 'package:glue_strategies/src/fs/local_workspace.dart';
export 'package:glue_strategies/src/fs/workspace.dart';
export 'package:glue_strategies/src/llm/anthropic_client.dart';
export 'package:glue_strategies/src/llm/message_mapper.dart';
export 'package:glue_strategies/src/llm/ndjson.dart';
export 'package:glue_strategies/src/llm/ollama_client.dart';
export 'package:glue_strategies/src/llm/openai_client.dart';
export 'package:glue_strategies/src/llm/sse.dart';
export 'package:glue_strategies/src/llm/tool_schema.dart';
export 'package:glue_strategies/src/mcp_client/auth_flow.dart';
export 'package:glue_strategies/src/mcp_client/client.dart';
export 'package:glue_strategies/src/mcp_client/config.dart';
export 'package:glue_strategies/src/mcp_client/connection_state.dart';
export 'package:glue_strategies/src/mcp_client/oauth.dart';
export 'package:glue_strategies/src/mcp_client/pool.dart';
export 'package:glue_strategies/src/mcp_client/protocol.dart';
export 'package:glue_strategies/src/mcp_client/tool_factory.dart';
export 'package:glue_strategies/src/mcp_client/transport/http_sse.dart';
export 'package:glue_strategies/src/mcp_client/transport/stdio.dart';
export 'package:glue_strategies/src/mcp_client/transport/websocket.dart';
export 'package:glue_strategies/src/providers/anthropic_adapter.dart';
export 'package:glue_strategies/src/providers/auth_flow.dart';
export 'package:glue_strategies/src/providers/compatibility_profile.dart';
export 'package:glue_strategies/src/providers/copilot_adapter.dart';
export 'package:glue_strategies/src/providers/copilot_token_manager.dart';
export 'package:glue_strategies/src/providers/gemini_provider.dart';
export 'package:glue_strategies/src/providers/ollama_adapter.dart';
export 'package:glue_strategies/src/providers/ollama_discovery.dart';
export 'package:glue_strategies/src/providers/openai_compatible_adapter.dart';
export 'package:glue_strategies/src/providers/provider_adapter.dart';
export 'package:glue_strategies/src/providers/resolved.dart';
export 'package:glue_strategies/src/runtime/runtime_factory.dart';
export 'package:glue_strategies/src/shell/command_executor.dart';
export 'package:glue_strategies/src/shell/docker_config.dart';
export 'package:glue_strategies/src/shell/docker_executor.dart';
export 'package:glue_strategies/src/shell/executor_factory.dart';
export 'package:glue_strategies/src/shell/host_executor.dart';
export 'package:glue_strategies/src/shell/line_ring_buffer.dart';
export 'package:glue_strategies/src/shell/shell_completer.dart';
export 'package:glue_strategies/src/shell/shell_config.dart';
export 'package:glue_strategies/src/web/browser/browser_config.dart';
export 'package:glue_strategies/src/web/browser/browser_endpoint.dart';
export 'package:glue_strategies/src/web/browser/browser_manager.dart';
export 'package:glue_strategies/src/web/browser/providers/anchor_provider.dart';
export 'package:glue_strategies/src/web/browser/providers/browserbase_provider.dart';
export 'package:glue_strategies/src/web/browser/providers/browserless_provider.dart';
export 'package:glue_strategies/src/web/browser/providers/docker_browser_provider.dart';
export 'package:glue_strategies/src/web/browser/providers/hyperbrowser_provider.dart';
export 'package:glue_strategies/src/web/browser/providers/local_provider.dart';
export 'package:glue_strategies/src/web/browser/providers/steel_provider.dart';
export 'package:glue_strategies/src/web/fetch/html_extractor.dart';
export 'package:glue_strategies/src/web/fetch/html_to_markdown.dart';
export 'package:glue_strategies/src/web/fetch/jina_reader_client.dart';
export 'package:glue_strategies/src/web/fetch/ocr_client.dart';
export 'package:glue_strategies/src/web/fetch/pdf_text_extractor.dart';
export 'package:glue_strategies/src/web/fetch/truncation.dart';
export 'package:glue_strategies/src/web/fetch/web_fetch_client.dart';
export 'package:glue_strategies/src/web/search/models.dart';
export 'package:glue_strategies/src/web/search/provider.dart';
export 'package:glue_strategies/src/web/search/providers/brave_provider.dart';
export 'package:glue_strategies/src/web/search/providers/duckduckgo_provider.dart';
export 'package:glue_strategies/src/web/search/providers/firecrawl_provider.dart';
export 'package:glue_strategies/src/web/search/providers/tavily_provider.dart';
export 'package:glue_strategies/src/web/search/search_router.dart';
export 'package:glue_strategies/src/web/web_config.dart';
