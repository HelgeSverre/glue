import 'dart:async';

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/agent_runner.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/llm/llm_factory.dart';
import 'package:glue/src/tools/subagent_tools.dart';

/// Tools that are safe for subagents to execute without user approval.
const safeSubagentTools = {'read_file', 'list_directory', 'grep'};

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

  final _updateController = StreamController<SubagentUpdate>.broadcast();

  /// Stream of updates from running subagents.
  Stream<SubagentUpdate> get updates => _updateController.stream;

  AgentManager({
    required this.tools,
    required this.llmFactory,
    required this.config,
    required this.systemPrompt,
    Set<String>? allowedSubagentTools,
  }) : allowedSubagentTools = allowedSubagentTools ?? safeSubagentTools;

  /// Spawn a single subagent to complete a [task].
  ///
  /// Optionally override [profile] for model/provider selection.
  /// [currentDepth] tracks recursion to prevent infinite nesting.
  /// [index] and [total] are set when spawned as part of a parallel batch.
  Future<String> spawnSubagent({
    required String task,
    AgentProfile? profile,
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

    final effectiveProfile =
        profile ?? AgentProfile(provider: config.provider, model: config.model);

    final llm = llmFactory.create(
      provider: effectiveProfile.provider,
      model: effectiveProfile.model,
      apiKey: _apiKeyFor(effectiveProfile.provider),
      systemPrompt: systemPrompt,
    );

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

    final core = AgentCore(
      llm: llm,
      tools: subagentTools,
      modelName: effectiveProfile.model,
    );

    final runner = AgentRunner(
      core: core,
      policy: ToolApprovalPolicy.allowlist,
      allowedTools: allowedSubagentTools,
      onEvent: (event) => _updateController.add(SubagentUpdate(
        task: task,
        index: index,
        total: total,
        event: event,
      )),
    );

    return runner.runToCompletion(task);
  }

  /// Spawn [tasks] in parallel, each as an independent subagent.
  ///
  /// All subagents run concurrently and results are returned in order.
  ///
  /// **Note:** Parallel subagents share the same file system. Avoid
  /// tasks that write to the same files concurrently, as this can
  /// cause race conditions.
  Future<List<String>> spawnParallel({
    required List<String> tasks,
    AgentProfile? profile,
    int currentDepth = 0,
  }) async {
    return Future.wait([
      for (var i = 0; i < tasks.length; i++)
        spawnSubagent(
          task: tasks[i],
          profile: profile,
          currentDepth: currentDepth,
          index: i,
          total: tasks.length,
        ),
    ]);
  }

  String _apiKeyFor(LlmProvider provider) => switch (provider) {
        LlmProvider.anthropic => config.anthropicApiKey ?? '',
        LlmProvider.openai => config.openaiApiKey ?? '',
        LlmProvider.ollama => '',
      };
}
