import 'dart:convert';

import 'package:glue/src/agent/agent_manager.dart';
import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/catalog/model_ref.dart';

/// Tool that spawns a single subagent to perform a focused task.
class SpawnSubagentTool extends Tool {
  SpawnSubagentTool(this._manager, {int depth = 0}) : _depth = depth;

  final AgentManager _manager;
  final int _depth;

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
          name: 'model_ref',
          type: 'string',
          description: 'Override model as `<provider>/<model>` (e.g. '
              '"anthropic/claude-haiku-4.5"). Defaults to the active model.',
          required: false,
        ),
      ];

  @override
  Future<List<ContentPart>> execute(Map<String, dynamic> args) async {
    final task = args['task'] as String;
    final override = args['model_ref'] as String?;
    final ref = override != null ? ModelRef.parse(override) : null;

    final result = await _manager.spawnSubagent(
      task: task,
      modelOverride: ref,
      currentDepth: _depth,
    );
    return [TextPart(result)];
  }
}

/// Tool that spawns multiple subagents in parallel.
class SpawnParallelSubagentsTool extends Tool {
  SpawnParallelSubagentsTool(this._manager, {int depth = 0}) : _depth = depth;

  final AgentManager _manager;
  final int _depth;

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
          name: 'model_ref',
          type: 'string',
          description: 'Override model as `<provider>/<model>`.',
          required: false,
        ),
      ];

  @override
  Future<List<ContentPart>> execute(Map<String, dynamic> args) async {
    final tasks = (args['tasks'] as List).cast<String>();
    final override = args['model_ref'] as String?;
    final ref = override != null ? ModelRef.parse(override) : null;

    final results = await _manager.spawnParallel(
      tasks: tasks,
      modelOverride: ref,
      currentDepth: _depth,
    );

    return [
      TextPart(
        jsonEncode({
          'results': [
            for (var i = 0; i < tasks.length; i++)
              {'task': tasks[i], 'output': results[i]},
          ],
        }),
      ),
    ];
  }
}
