/// Pure-data type vocabulary shared across Glue's harness, strategies,
/// and surfaces.
///
/// This package is deliberately dependency-free. Anything that needs
/// HTTP, file I/O, or a runtime service belongs in a higher layer (see
/// `docs/plans/2026-04-29-harness-layers.md`).
///
/// Re-exports:
///
/// - Identity types ([SessionId], [ProjectId], …)
/// - Conversation messages and tool-call vocabulary ([Message],
///   [ToolCall], [LlmChunk], [Tool], [ToolResult])
/// - The current agent event vocabulary ([AgentEvent] and variants)
/// - The proposed surface↔harness contract ([SessionEvent],
///   [SessionCommand] and variants)
/// - Catalog data types ([ModelRef], [ModelCatalog], [ProviderDef])
/// - [AppConstants] (timeouts, defaults, package version)
library;

export 'package:glue_core/src/agent_event.dart';
export 'package:glue_core/src/app_constants.dart';
export 'package:glue_core/src/content_part.dart';
export 'package:glue_core/src/ids.dart';
export 'package:glue_core/src/llm_client.dart';
export 'package:glue_core/src/message.dart';
export 'package:glue_core/src/model_catalog.dart';
export 'package:glue_core/src/model_ref.dart';
export 'package:glue_core/src/session_command.dart';
export 'package:glue_core/src/session_event.dart';
export 'package:glue_core/src/tool.dart';
export 'package:glue_core/src/usage_report.dart';
export 'package:glue_core/src/usage_stats.dart';
