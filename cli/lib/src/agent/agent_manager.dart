import 'agent_core.dart';
import 'agent_runner.dart';
import 'tools.dart';
import '../config/glue_config.dart';
import '../llm/llm_factory.dart';

/// Orchestrates subagent spawning using the manager pattern.
///
/// Creates independent [AgentCore] instances with their own conversation
/// history but shared tool registry. Subagents run headlessly via
/// [AgentRunner] with auto-approve policy.
class AgentManager {
  final Map<String, Tool> tools;
  final LlmClientFactory llmFactory;
  final GlueConfig config;
  final String systemPrompt;

  AgentManager({
    required this.tools,
    required this.llmFactory,
    required this.config,
    required this.systemPrompt,
  });

  /// Spawn a single subagent to complete a [task].
  ///
  /// Optionally override [profile] for model/provider selection.
  /// [currentDepth] tracks recursion to prevent infinite nesting.
  Future<String> spawnSubagent({
    required String task,
    AgentProfile? profile,
    int currentDepth = 0,
  }) async {
    if (currentDepth >= config.maxSubagentDepth) {
      throw Exception(
        'Maximum subagent depth (${config.maxSubagentDepth}) exceeded. '
        'Cannot spawn deeper subagents.',
      );
    }

    final effectiveProfile = profile ??
        AgentProfile(provider: config.provider, model: config.model);

    final llm = llmFactory.create(
      provider: effectiveProfile.provider,
      model: effectiveProfile.model,
      apiKey: _apiKeyFor(effectiveProfile.provider),
      systemPrompt: systemPrompt,
    );

    // Subagents get all tools except subagent-spawning tools
    // to prevent infinite recursion at the tool level.
    final subagentTools = Map<String, Tool>.from(tools)
      ..removeWhere((name, _) =>
          name == 'spawn_subagent' || name == 'spawn_parallel_subagents');

    final core = AgentCore(
      llm: llm,
      tools: subagentTools,
      modelName: effectiveProfile.model,
    );

    final runner = AgentRunner(
      core: core,
      policy: ToolApprovalPolicy.autoApproveAll,
    );

    return runner.runToCompletion(task);
  }

  /// Spawn [tasks] in parallel, each as an independent subagent.
  ///
  /// All subagents run concurrently and results are returned in order.
  Future<List<String>> spawnParallel({
    required List<String> tasks,
    AgentProfile? profile,
    int currentDepth = 0,
  }) async {
    return Future.wait([
      for (final task in tasks)
        spawnSubagent(
          task: task,
          profile: profile,
          currentDepth: currentDepth,
        ),
    ]);
  }

  String _apiKeyFor(LlmProvider provider) => switch (provider) {
        LlmProvider.anthropic => config.anthropicApiKey ?? '',
        LlmProvider.openai => config.openaiApiKey ?? '',
        LlmProvider.ollama => '',
      };
}
