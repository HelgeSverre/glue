/// Tool abstraction shared by the agent loop and the LLM strategies.
///
/// **Status:** part of the proposed core data model — see
/// `docs/plans/2026-04-29-harness-layers.md`. Originally lived in
/// `agent/tools.dart`; relocated so strategies (LLM clients, providers)
/// can depend on these types without crossing the harness boundary.
///
/// Tool implementations (ReadFileTool, BashTool, …) stay in `agent/tools.dart`
/// because they pull in I/O and runtime dependencies. Only the abstract
/// surface area moves here.
library;

import 'dart:async';

import 'package:glue_core/src/content_part.dart';
import 'package:glue_core/src/ids.dart';

/// Schema for a single tool parameter.
class ToolParameter {
  final String name;
  final String type;
  final String description;
  final bool required;

  /// JSON Schema for array element type. Required by OpenAI's strict
  /// function-calling validator when [type] is `'array'`.
  final Map<String, dynamic>? items;

  const ToolParameter({
    required this.name,
    required this.type,
    required this.description,
    this.required = true,
    this.items,
  });

  Map<String, dynamic> toSchema() {
    return {
      'type': type,
      'description': description,
      if (items != null) 'items': items,
    };
  }
}

/// How much trust a tool requires from the permission system.
enum ToolTrust {
  /// Read-only or side-effect-free tools. Auto-approved in most modes.
  safe,

  /// Tools that create or modify files.
  fileEdit,

  /// Tools that execute arbitrary shell commands.
  command,
}

/// Structured result of a tool invocation.
///
/// Tools produce a [ToolResult] with [callId] left as the empty
/// [ToolCallId] — the agent fills it in via [withCallId] when wrapping
/// the result for the conversation envelope. The [content] string is what
/// the LLM sees; [summary] is an optional one-liner preferred by the UI;
/// [metadata] carries structured fields (bytes, line_count, exit_code,
/// paths, …).
class ToolResult {
  /// The call-site identifier, set by the agent. Empty when produced
  /// directly by a [Tool].
  final ToolCallId callId;

  /// Whether the invocation succeeded. `false` flags the UI and LLM that
  /// the tool could not complete its task.
  final bool success;

  /// Primary payload sent to the LLM. For errors, a human-readable
  /// description.
  final String content;

  /// Optional one-liner preferred by the UI (e.g. "Read foo.dart (42
  /// lines)"). When `null`, renderers fall back to truncating [content].
  final String? summary;

  /// Structured metadata populated by the tool (bytes, line_count,
  /// exit_code, match_count, entry_count, etc.). Always non-null.
  final Map<String, dynamic> metadata;

  /// Multimodal artifacts (e.g. screenshots). When present, these replace
  /// [content] in the LLM payload.
  final List<ContentPart>? contentParts;

  ToolResult({
    this.callId = const ToolCallId(''),
    this.success = true,
    required this.content,
    this.summary,
    Map<String, dynamic>? metadata,
    this.contentParts,
  }) : metadata = metadata ?? const {};

  factory ToolResult.denied(ToolCallId callId) => ToolResult(
    callId: callId,
    success: false,
    content: 'User denied tool execution',
  );

  /// Returns a copy with [callId] set. The agent invokes this to stamp a
  /// tool's bare output with the originating call's identifier.
  ToolResult withCallId(ToolCallId id) => ToolResult(
    callId: id,
    success: success,
    content: content,
    summary: summary,
    metadata: metadata,
    contentParts: contentParts,
  );

  /// Serialises the LLM-facing payload into [ContentPart]s.
  ///
  /// When [contentParts] is non-null (e.g. a screenshot) those parts are
  /// returned directly; otherwise [content] is wrapped in a single
  /// [TextPart].
  List<ContentPart> toContentParts() {
    if (contentParts != null) return contentParts!;
    return [TextPart(content)];
  }
}

/// Base class for all tools available to the agent.
///
/// Each tool declares its [name], [description], and [parameters] so the
/// LLM can decide when and how to invoke it. The [execute] method
/// performs the actual work and returns a [ToolResult].
///
/// {@category Tools}
abstract class Tool {
  /// Machine-readable tool name (e.g. `read_file`).
  String get name;

  /// Human-readable description shown to the LLM.
  String get description;

  /// Parameter definitions used to build the JSON schema sent to the LLM.
  List<ToolParameter> get parameters;

  /// Subset of [parameters] where [ToolParameter.required] is true.
  List<ToolParameter> get requiredParameters =>
      parameters.where((p) => p.required).toList();

  /// Executes this tool with the given [args] and returns a [ToolResult].
  ///
  /// Implementations should leave [ToolResult.callId] as its default
  /// (empty) — the agent stamps it in via [ToolResult.withCallId] when
  /// wrapping the result for the conversation.
  Future<ToolResult> execute(Map<String, dynamic> args);

  /// The trust level this tool requires. Defaults to [ToolTrust.safe].
  ToolTrust get trust => ToolTrust.safe;

  /// Whether this tool can mutate state (files, shell commands, etc.).
  bool get isMutating => trust != ToolTrust.safe;

  /// Releases any resources held by this tool.
  Future<void> dispose() async {}

  /// Builds the JSON schema representation for this tool.
  Map<String, dynamic> toSchema() {
    return {
      'name': name,
      'description': description,
      'input_schema': {
        'type': 'object',
        'properties': Map.fromEntries(
          parameters.map((p) => MapEntry(p.name, p.toSchema())),
        ),
        'required': requiredParameters.map((p) => p.name).toList(),
      },
    };
  }
}

/// Base class for tool decorators. Forwards all methods to [inner].
///
/// Extend this and override only what you need. When new methods are
/// added to [Tool], only this class needs updating — all decorators
/// inherit the forwarding automatically.
class ForwardingTool extends Tool {
  final Tool inner;

  ForwardingTool(this.inner);

  @override
  String get name => inner.name;

  @override
  String get description => inner.description;

  @override
  List<ToolParameter> get parameters => inner.parameters;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) => inner.execute(args);

  @override
  ToolTrust get trust => inner.trust;

  @override
  bool get isMutating => inner.isMutating;

  @override
  Future<void> dispose() => inner.dispose();

  @override
  Map<String, dynamic> toSchema() => inner.toSchema();
}
