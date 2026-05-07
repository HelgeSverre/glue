/// Glue's harness layer.
///
/// Above this package: surfaces (CLI, ACP server, web UI) that consume
/// the harness API. Below this package: `glue_strategies` (wire-format
/// implementations) and `glue_core` (pure data types).
///
/// The harness owns the agent loop, session lifecycle, permission
/// gating, observability, the model catalog, and the tool implementations
/// that wrap strategy primitives. See
/// `docs/plans/2026-04-29-harness-layers.md`.
library;

export 'package:glue_harness/src/agent/agent_core.dart';
export 'package:glue_harness/src/agent/agent_manager.dart';
export 'package:glue_harness/src/agent/agent_runner.dart';
export 'package:glue_harness/src/agent/llm_factory.dart';
export 'package:glue_harness/src/agent/prompts.dart';
export 'package:glue_harness/src/agent/recap_generator.dart';
export 'package:glue_harness/src/agent/shell_job_manager.dart';
export 'package:glue_harness/src/agent/title_generator.dart';
export 'package:glue_harness/src/agent/tools.dart';
export 'package:glue_harness/src/catalog/catalog_loader.dart';
export 'package:glue_harness/src/catalog/catalog_parser.dart';
export 'package:glue_harness/src/catalog/catalog_refresh_service.dart';
export 'package:glue_harness/src/catalog/model_resolver.dart';
export 'package:glue_harness/src/catalog/models_generated.dart';
export 'package:glue_harness/src/catalog/remote_catalog_fetcher.dart';
export 'package:glue_harness/src/catalog/remote_catalog_sanitizer.dart';
export 'package:glue_harness/src/config/approval_mode.dart';
export 'package:glue_harness/src/config/build_info.dart';
export 'package:glue_harness/src/config/config_template.dart';
export 'package:glue_harness/src/config/glue_config.dart';
export 'package:glue_harness/src/core/clipboard.dart';
export 'package:glue_harness/src/core/environment.dart';
// Both path_opener and url_launcher define a private `ProcessRunner`
// typedef for testing. Hide it from path_opener's export so the barrel's
// public surface stays unambiguous.
export 'package:glue_harness/src/core/path_opener.dart' hide ProcessRunner;
export 'package:glue_harness/src/core/service_locator.dart';
export 'package:glue_harness/src/core/url_launcher.dart';
export 'package:glue_harness/src/core/where_report.dart';
export 'package:glue_harness/src/extensions/units.dart';
export 'package:glue_harness/src/observability/debug_controller.dart';
export 'package:glue_harness/src/observability/file_sink.dart';
export 'package:glue_harness/src/observability/http_trace_sink.dart';
export 'package:glue_harness/src/observability/logging_http_client.dart';
export 'package:glue_harness/src/observability/observability.dart';
export 'package:glue_harness/src/observability/observability_config.dart';
export 'package:glue_harness/src/observability/otlp_http_trace_sink.dart';
export 'package:glue_harness/src/observability/redaction.dart';
export 'package:glue_harness/src/orchestrator/permission_gate.dart';
export 'package:glue_harness/src/orchestrator/tool_permissions.dart';
export 'package:glue_harness/src/session/session_event_normalizer.dart';
export 'package:glue_harness/src/session/session_manager.dart';
export 'package:glue_harness/src/share/gist_publisher.dart';
export 'package:glue_harness/src/share/html/share_html_assets_loader.dart';
export 'package:glue_harness/src/share/renderer/html_renderer.dart';
export 'package:glue_harness/src/share/renderer/markdown_renderer.dart';
export 'package:glue_harness/src/share/renderer/renderer_support.dart';
export 'package:glue_harness/src/share/session_share_exporter.dart';
export 'package:glue_harness/src/share/share_models.dart';
export 'package:glue_harness/src/share/share_transcript_builder.dart';
export 'package:glue_harness/src/skills/skill_activation.dart';
export 'package:glue_harness/src/skills/skill_parser.dart';
export 'package:glue_harness/src/skills/skill_paths.dart';
export 'package:glue_harness/src/skills/skill_registry.dart';
export 'package:glue_harness/src/skills/skill_runtime.dart';
export 'package:glue_harness/src/skills/skill_tool.dart';
export 'package:glue_harness/src/storage/config_store.dart';
export 'package:glue_harness/src/storage/session_state.dart';
export 'package:glue_harness/src/storage/session_store.dart';
export 'package:glue_harness/src/tools/subagent_tools.dart';
export 'package:glue_harness/src/tools/web_browser_tool.dart';
export 'package:glue_harness/src/tools/web_fetch_tool.dart';
export 'package:glue_harness/src/tools/web_search_tool.dart';
