import 'dart:async';
import 'dart:math';

import 'package:glue_harness/src/agent/agent_core.dart';
import 'package:glue_harness/src/agent/agent_runner.dart';
import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/src/config/glue_config.dart';
import 'package:glue_harness/src/agent/llm_factory.dart';
import 'package:glue_harness/src/observability/observability.dart';
import 'package:glue_harness/src/orchestrator/tool_permissions.dart';
import 'package:glue_harness/src/tools/subagent_tools.dart';

/// Signature for persisting subagent activity onto the parent session log.
///
/// Wired by surfaces (CLI, ACP server) to `SessionManager.logEvent` so the
/// transcript can be replayed and shared. Three event types are emitted:
/// `subagent_spawned`, `subagent_event`, `subagent_completed`. The
/// `subagent_event` payload nests a serialised inner [AgentEvent] under
/// `inner`.
typedef SubagentEventSink = void Function(
    String type, Map<String, dynamic> data);

/// An update from a running subagent, forwarded to the UI.
class SubagentUpdate {
  /// Short description of the subagent's task.
  final String task;

  /// Index within a parallel batch (null for single subagent).
  final int? index;

  /// Total number of parallel subagents (null for single).
  final int? total;

  /// The underlying agent event.
  final AgentEvent event;

  SubagentUpdate({
    required this.task,
    this.index,
    this.total,
    required this.event,
  });
}

/// Orchestrates subagent spawning using the manager pattern.
///
/// {@category Agent}
///
/// Creates independent [AgentCore] instances with their own conversation
/// history but shared tool registry. Subagents run headlessly via
/// [AgentRunner] with an allowlist-based approval policy (read-only
/// tools by default).
class AgentManager {
  final Map<String, Tool> tools;
  final LlmClientFactory llmFactory;
  final GlueConfig config;
  final String systemPrompt;
  final Set<String> allowedSubagentTools;
  final Observability? obs;

  /// Optional sink for persisting subagent activity onto the parent session
  /// log. Surfaces wire this to `SessionManager.logEvent` so subagent
  /// transcripts survive resume and feed `/share`. When `null`, subagent
  /// activity remains live-only (the legacy behavior).
  SubagentEventSink? onPersistEvent;

  /// Cumulative usage across every subagent this manager has spawned.
  /// Surfaces (CLI status bar, ACP usage endpoint) read this to attribute
  /// subagent cost separately from the parent agent's own LLM calls.
  final UsageStats subagentStats = UsageStats();

  /// Optional callback invoked when a subagent finishes, with that
  /// subagent's [UsageStats]. Surfaces wire this to
  /// `SessionManager.recordUsage(stats, role: 'subagent')` so the rollup
  /// is also persisted.
  void Function(UsageStats)? onSubagentUsage;

  final _updateController = StreamController<SubagentUpdate>.broadcast();
  final _idRandom = Random();

  /// Stream of updates from running subagents.
  Stream<SubagentUpdate> get updates => _updateController.stream;

  AgentManager({
    required this.tools,
    required this.llmFactory,
    required this.config,
    required this.systemPrompt,
    Set<String>? allowedSubagentTools,
    this.obs,
    this.onPersistEvent,
  }) : allowedSubagentTools =
            allowedSubagentTools ?? ToolPermissions.subagentSafeTools;

  SubagentId _mintSubagentId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rand = _idRandom.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
    return SubagentId('sub-$ts-$rand');
  }

  /// Spawns a single subagent to complete a [task].
  ///
  /// Optionally override [modelOverride] to switch model for this subagent.
  /// [currentDepth] tracks recursion to prevent infinite nesting.
  /// [index] and [total] are set when spawned as part of a parallel batch.
  Future<String> spawnSubagent({
    required String task,
    ModelRef? modelOverride,
    int currentDepth = 0,
    int? index,
    int? total,
  }) async {
    if (currentDepth >= config.maxSubagentDepth) {
      throw Exception(
        'Maximum subagent depth (${config.maxSubagentDepth}) exceeded. '
        'Cannot spawn deeper subagents.',
      );
    }

    final ref = modelOverride ?? config.activeModel;
    final llm = llmFactory.createFor(ref, systemPrompt: systemPrompt);

    final subagentTools = Map<String, Tool>.from(tools);

    // Give subagents depth-incremented spawning tools if they haven't
    // reached the maximum depth yet.
    final nextDepth = currentDepth + 1;
    if (nextDepth < config.maxSubagentDepth) {
      subagentTools['spawn_subagent'] =
          SpawnSubagentTool(this, depth: nextDepth);
      subagentTools['spawn_parallel_subagents'] =
          SpawnParallelSubagentsTool(this, depth: nextDepth);
    } else {
      subagentTools.removeWhere((name, _) =>
          name == 'spawn_subagent' || name == 'spawn_parallel_subagents');
    }

    // Create a span for the subagent execution.
    final span = obs?.startSpan(
      'subagent',
      kind: 'subagent',
      attributes: {
        'subagent.task': task,
        'subagent.depth': currentDepth,
        'subagent.model': ref.toString(),
        if (index != null) 'subagent.index': index,
        if (total != null) 'subagent.total': total,
      },
    );

    final subagentId = _mintSubagentId();
    onPersistEvent?.call('subagent_spawned', {
      'subagent_id': subagentId.value,
      'task': task,
      'depth': currentDepth,
      if (index != null) 'index': index,
      if (total != null) 'total': total,
      'model': ref.toString(),
    });

    final core = AgentCore(
      llm: llm,
      tools: subagentTools,
      modelId: ref.modelId,
      obs: obs,
      traceParent: span,
    );

    final runner = AgentRunner(
      core: core,
      policy: ToolApprovalPolicy.allowlist,
      allowedTools: allowedSubagentTools,
      onEvent: (event) {
        onPersistEvent?.call('subagent_event', {
          'subagent_id': subagentId.value,
          'inner': serializeAgentEvent(event),
        });
        _updateController.add(SubagentUpdate(
          task: task,
          index: index,
          total: total,
          event: event,
        ));
      },
    );

    try {
      final result = await runner.runToCompletion(task);
      _finaliseSubagentUsage(subagentId, runner.stats);
      onPersistEvent?.call('subagent_completed', {
        'subagent_id': subagentId.value,
      });
      if (span != null) obs!.endSpan(span);
      return result;
    } catch (e) {
      _finaliseSubagentUsage(subagentId, runner.stats);
      onPersistEvent?.call('subagent_completed', {
        'subagent_id': subagentId.value,
        'error': e.toString(),
      });
      if (span != null) obs!.endSpan(span, extra: {'error': e.toString()});
      rethrow;
    }
  }

  void _finaliseSubagentUsage(SubagentId subagentId, UsageStats subagent) {
    if (subagent.turnCount == 0) return;
    subagentStats.merge(subagent);
    onPersistEvent?.call('subagent_usage', {
      'subagent_id': subagentId.value,
      ...subagent.toJson(),
    });
    onSubagentUsage?.call(subagent.snapshot());
  }

  /// Spawns [tasks] in parallel, each as independent subagents.
  ///
  /// All subagents run concurrently and results are returned in order.
  ///
  /// **Note:** Parallel subagents share the same file system. Avoid
  /// tasks that write to the same files concurrently, as this can
  /// cause race conditions.
  Future<List<String>> spawnParallel({
    required List<String> tasks,
    ModelRef? modelOverride,
    int currentDepth = 0,
  }) async {
    return Future.wait([
      for (var i = 0; i < tasks.length; i++)
        spawnSubagent(
          task: tasks[i],
          modelOverride: modelOverride,
          currentDepth: currentDepth,
          index: i,
          total: tasks.length,
        ),
    ]);
  }
}

/// Serialises an [AgentEvent] into a JSON-compatible map for persistence
/// in the parent session log under `subagent_event.inner`. The shape mirrors
/// the top-level conversation event types where they overlap (`tool_call`,
/// `tool_result`, `assistant_message`) so the same normaliser can recurse
/// into either.
Map<String, dynamic> serializeAgentEvent(AgentEvent event) {
  return switch (event) {
    AgentTextDelta(:final delta) => {
        'type': 'assistant_message',
        'text': delta,
      },
    AgentThinkingDelta(:final delta) => {
        'type': 'assistant_thinking',
        'text': delta,
      },
    AgentToolCallPending(:final id, :final name) => {
        'type': 'tool_call_pending',
        'id': id.value,
        'name': name,
      },
    AgentToolCall(:final call) => {
        'type': 'tool_call',
        'id': call.id.value,
        'name': call.name,
        'arguments': call.arguments,
      },
    AgentToolResult(:final result) => {
        'type': 'tool_result',
        'call_id': result.callId.value,
        'success': result.success,
        'content': result.content,
        if (result.summary != null) 'summary': result.summary,
      },
    AgentDone() => {'type': 'agent_done'},
    AgentError(:final error) => {
        'type': 'agent_error',
        'error': error.toString(),
      },
    AgentUsage(:final usage) => {
        'type': 'usage',
        'input_tokens': usage.inputTokens,
        'output_tokens': usage.outputTokens,
        if (usage.cacheReadTokens != null)
          'cache_read_tokens': usage.cacheReadTokens,
        if (usage.cacheCreationTokens != null)
          'cache_creation_tokens': usage.cacheCreationTokens,
      },
  };
}
