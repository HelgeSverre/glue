import 'dart:async';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/orchestrator/tool_permissions.dart';
import 'package:glue/src/providers/llm_client_factory.dart';
import 'package:glue/src/tools/subagent_tools.dart';

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

/// Spawns headless [Agent]s for delegated tasks.
///
/// {@category Agent}
///
/// Each spawned subagent is an independent [Agent] with its own
/// conversation history but a shared tool registry. They run via
/// [Agent.runHeadless] with an allowlist-based approval policy (read-only
/// tools by default), and their events are broadcast on [updates] so the
/// UI can render progress.
class Subagents {
  final Map<String, Tool> tools;
  final LlmClientFactory llmFactory;
  final GlueConfig config;
  final String systemPrompt;
  final Set<String> allowedSubagentTools;
  final Observability? obs;

  final _updateController = StreamController<SubagentUpdate>.broadcast();

  /// Stream of updates from running subagents.
  Stream<SubagentUpdate> get updates => _updateController.stream;

  Subagents({
    required this.tools,
    required this.llmFactory,
    required this.config,
    required this.systemPrompt,
    Set<String>? allowedSubagentTools,
    this.obs,
  }) : allowedSubagentTools =
            allowedSubagentTools ?? ToolPermissions.subagentSafeTools;

  /// Spawns a single subagent to complete a [task].
  ///
  /// Optionally override [modelOverride] to switch model for this subagent.
  /// [currentDepth] tracks recursion to prevent infinite nesting.
  /// [index] and [total] are set when spawned as part of a parallel batch.
  Future<String> spawn({
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

    final agent = Agent(
      llm: llm,
      tools: subagentTools,
      modelId: ref.modelId,
      obs: obs,
      traceParent: span,
    );

    try {
      final result = await agent.runHeadless(
        task,
        policy: ToolApprovalPolicy.allowlist,
        allowedTools: allowedSubagentTools,
        onEvent: (event) => _updateController.add(SubagentUpdate(
          task: task,
          index: index,
          total: total,
          event: event,
        )),
      );
      if (span != null) obs!.endSpan(span);
      return result;
    } catch (e) {
      if (span != null) obs!.endSpan(span, extra: {'error': e.toString()});
      rethrow;
    }
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
        spawn(
          task: tasks[i],
          modelOverride: modelOverride,
          currentDepth: currentDepth,
          index: i,
          total: tasks.length,
        ),
    ]);
  }
}
