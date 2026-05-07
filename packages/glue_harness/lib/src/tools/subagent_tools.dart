import 'dart:convert';

import 'package:glue_harness/src/agent/agent_manager.dart';
import 'package:glue_core/glue_core.dart';

/// Tool that spawns a single subagent to perform a focused task.
class SpawnSubagentTool extends Tool {
  SpawnSubagentTool(
    this._manager, {
    int depth = 0,
    String? parentSubagentId,
  })  : _depth = depth,
        _parentSubagentId = parentSubagentId;

  final AgentManager _manager;
  final int _depth;
  final String? _parentSubagentId;

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
              '"anthropic/claude-haiku-4-5"). Defaults to the active model.',
          required: false,
        ),
      ];

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final task = args['task'] as String;
    final override = args['model_ref'] as String?;
    final ref = override != null ? ModelRef.parse(override) : null;

    final result = await _manager.spawnSubagent(
      task: task,
      modelOverride: ref,
      currentDepth: _depth,
      parentSubagentId: _parentSubagentId,
    );
    return ToolResult(
      content: result,
      summary: 'subagent: $task',
      metadata: {
        'task': task,
        if (override != null) 'model_ref': override,
        'depth': _depth,
      },
    );
  }
}

/// Tool that spawns multiple subagents in parallel.
class SpawnParallelSubagentsTool extends Tool {
  SpawnParallelSubagentsTool(
    this._manager, {
    int depth = 0,
    String? parentSubagentId,
  })  : _depth = depth,
        _parentSubagentId = parentSubagentId;

  final AgentManager _manager;
  final int _depth;
  final String? _parentSubagentId;

  @override
  String get name => 'spawn_parallel_subagents';

  @override
  String get description =>
      'Spawn multiple subagents to work on independent tasks in parallel. '
      'Each subagent has its own conversation and tools. '
      'Results are returned as a JSON array. '
      'Do not include a synthesis or aggregation task in the same parallel '
      'batch as the tasks it depends on — synthesis subagents run '
      'concurrently with the others and will see no inputs. Run synthesis '
      'as a separate sequential spawn_subagent call after the parallel '
      'batch returns.';

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'tasks',
          type: 'array',
          description: 'List of task descriptions, one per subagent.',
          items: {'type': 'string'},
        ),
        ToolParameter(
          name: 'model_ref',
          type: 'string',
          description: 'Override model as `<provider>/<model>`.',
          required: false,
        ),
      ];

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final tasks = (args['tasks'] as List).cast<String>();
    final override = args['model_ref'] as String?;
    final ref = override != null ? ModelRef.parse(override) : null;

    final results = await _manager.spawnParallel(
      tasks: tasks,
      modelOverride: ref,
      currentDepth: _depth,
      parentSubagentId: _parentSubagentId,
    );

    final json = jsonEncode({
      'results': [
        for (var i = 0; i < tasks.length; i++)
          {'task': tasks[i], 'output': results[i]},
      ],
    });
    return ToolResult(
      content: json,
      summary: 'parallel subagents: ${tasks.length} tasks',
      metadata: {
        'task_count': tasks.length,
        if (override != null) 'model_ref': override,
        'depth': _depth,
      },
    );
  }
}
