part of 'package:glue/src/app.dart';

void _handleSubagentUpdateImpl(App app, SubagentUpdate update) {
  final groupKey = '${update.task}:${update.index ?? 0}';
  final group = app._subagentGroups.putIfAbsent(
    groupKey,
    () {
      final g = _SubagentGroup(
        task: update.task,
        index: update.index,
        total: update.total,
      );
      app._blocks.add(_ConversationEntry.subagentGroup(g));
      return g;
    },
  );

  final prefix =
      update.index != null ? '↳ [${update.index! + 1}/${update.total}]' : '↳';

  switch (update.event) {
    case AgentToolCall(:final call):
      group._currentTool = call.name;
      final argsPreview = call.arguments.entries
          .take(2)
          .map((e) => '${e.key}: ${e.value}')
          .join(', ');
      group.entries.add(_SubagentEntry('$prefix ▶ ${call.name}  $argsPreview'));
      app._render();
    case AgentToolResult(:final result):
      final preview = result.content.length > 80
          ? '${result.content.substring(0, 80)}…'
          : result.content;
      group.entries.add(_SubagentEntry(
        '$prefix ✓ ${preview.replaceAll('\n', ' ')}',
        rawContent: result.content.length > 80 ? result.content : null,
      ));
      app._render();
    case AgentError(:final error):
      group.entries.add(_SubagentEntry('$prefix ✗ Error: $error'));
      app._render();
    case AgentToolCallPending():
      break;
    case AgentTextDelta():
      break;
    case AgentDone():
      group.done = true;
      group._currentTool = null;
      app._render();
  }
}
