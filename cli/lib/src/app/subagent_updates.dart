part of 'package:glue/src/app.dart';

void _handleSubagentUpdateImpl(App app, SubagentUpdate update) {
  final groupKey = '${update.task}:${update.index ?? 0}';
  final group = app._transcript.subagentGroups.putIfAbsent(
    groupKey,
    () {
      final g = SubagentGroup(
        task: update.task,
        index: update.index,
        total: update.total,
      );
      app._transcript.blocks.add(ConversationEntry.subagentGroup(g));
      return g;
    },
  );

  final prefix =
      update.index != null ? '↳ [${update.index! + 1}/${update.total}]' : '↳';

  switch (update.event) {
    case AgentToolCall(:final call):
      group.currentTool = call.name;
      final argsPreview = call.arguments.entries
          .take(2)
          .map((e) => '${e.key}: ${e.value}')
          .join(', ');
      group.entries.add(SubagentEntry('$prefix ▶ ${call.name}  $argsPreview'));
      app._render();
    case AgentToolResult(:final result):
      final display = result.summary ??
          (result.content.length > 80
              ? '${result.content.substring(0, 80)}…'
              : result.content);
      group.entries.add(SubagentEntry(
        '$prefix ✓ ${display.replaceAll('\n', ' ')}',
        rawContent: result.summary != null || result.content.length > 80
            ? result.content
            : null,
      ));
      app._render();
    case AgentError(:final error):
      group.entries.add(SubagentEntry('$prefix ✗ Error: $error'));
      app._render();
    case AgentToolCallPending():
      break;
    case AgentTextDelta():
      break;
    case AgentDone():
      group.done = true;
      group.currentTool = null;
      app._render();
  }
}
