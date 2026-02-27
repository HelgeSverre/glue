import 'dart:convert';
import '../agent/agent_manager.dart';
import '../agent/tools.dart';
import '../config/glue_config.dart';

/// Tool that spawns a single subagent to perform a focused task.
class SpawnSubagentTool extends Tool {
  final AgentManager _manager;
  final int _depth;

  SpawnSubagentTool(this._manager, {int depth = 0}) : _depth = depth;

  @override
  String get name => 'spawn_subagent';

  @override
  String get description =>
      'Spawn a subagent to perform a focused task independently. '
      'The subagent has its own conversation and can use tools. '
      'Use this for tasks that benefit from a fresh context.';

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'task',
          type: 'string',
          description: 'The task description for the subagent.',
        ),
        ToolParameter(
          name: 'provider',
          type: 'string',
          description:
              'LLM provider: "anthropic" or "openai". Defaults to current.',
          required: false,
        ),
        ToolParameter(
          name: 'model',
          type: 'string',
          description:
              'Model name override (e.g. "claude-haiku-4-5", "gpt-4.1-nano").',
          required: false,
        ),
      ];

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final task = args['task'] as String;
    final providerStr = args['provider'] as String?;
    final model = args['model'] as String?;

    AgentProfile? profile;
    if (providerStr != null || model != null) {
      final provider = providerStr != null
          ? LlmProvider.values.firstWhere(
              (p) => p.name == providerStr,
              orElse: () => _manager.config.provider,
            )
          : _manager.config.provider;
      profile = AgentProfile(
        provider: provider,
        model: model ?? GlueConfig(provider: provider).model,
      );
    }

    return _manager.spawnSubagent(
      task: task,
      profile: profile,
      currentDepth: _depth,
    );
  }
}

/// Tool that spawns multiple subagents in parallel.
class SpawnParallelSubagentsTool extends Tool {
  final AgentManager _manager;
  final int _depth;

  SpawnParallelSubagentsTool(this._manager, {int depth = 0}) : _depth = depth;

  @override
  String get name => 'spawn_parallel_subagents';

  @override
  String get description =>
      'Spawn multiple subagents to work on independent tasks in parallel. '
      'Each subagent has its own conversation and tools. '
      'Results are returned as a JSON array.';

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'tasks',
          type: 'array',
          description: 'List of task descriptions, one per subagent.',
        ),
        ToolParameter(
          name: 'provider',
          type: 'string',
          description: 'LLM provider for all subagents.',
          required: false,
        ),
        ToolParameter(
          name: 'model',
          type: 'string',
          description: 'Model name for all subagents.',
          required: false,
        ),
      ];

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final tasks = (args['tasks'] as List).cast<String>();
    final providerStr = args['provider'] as String?;
    final model = args['model'] as String?;

    AgentProfile? profile;
    if (providerStr != null || model != null) {
      final provider = providerStr != null
          ? LlmProvider.values.firstWhere(
              (p) => p.name == providerStr,
              orElse: () => _manager.config.provider,
            )
          : _manager.config.provider;
      profile = AgentProfile(
        provider: provider,
        model: model ?? GlueConfig(provider: provider).model,
      );
    }

    final results = await _manager.spawnParallel(
      tasks: tasks,
      profile: profile,
      currentDepth: _depth,
    );

    return jsonEncode({
      'results': [
        for (var i = 0; i < tasks.length; i++)
          {'task': tasks[i], 'output': results[i]},
      ],
    });
  }
}
