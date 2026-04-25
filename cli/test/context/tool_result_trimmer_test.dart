import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/context/tool_result_trimmer.dart';
import 'package:test/test.dart';

List<Message> _makeConversation(int userTurns, {int toolResultTokens = 1000}) {
  final messages = <Message>[];
  for (var i = 0; i < userTurns; i++) {
    messages.add(Message.user('Turn $i'));
    messages.add(
      Message.assistant(
        text: 'Thinking…',
        toolCalls: [
          ToolCall(id: 'tc$i', name: 'read_file', arguments: {'path': 'f.txt'}),
        ],
      ),
    );
    messages.add(Message.toolResult(
      callId: 'tc$i',
      // Make the content large enough to exceed 200-token threshold
      content: 'x' * (toolResultTokens * 4),
      toolName: 'read_file',
    ));
  }
  return messages;
}

void main() {
  group('ToolResultTrimmer', () {
    test('returns conversation unchanged when turns ≤ keepRecentN', () {
      final conv = _makeConversation(3);
      const trimmer = ToolResultTrimmer(keepRecentN: 3);
      final result = trimmer.trim(conv);
      expect(result, conv);
    });

    test('trims large tool results older than keepRecentN turns', () {
      final conv = _makeConversation(5);
      const trimmer = ToolResultTrimmer(keepRecentN: 2);
      final result = trimmer.trim(conv);

      // Older tool results should be truncated.
      final toolResults =
          result.where((m) => m.role == Role.toolResult).toList();
      expect(toolResults, hasLength(5));

      // First 3 should be truncated (older than keepRecentN=2).
      for (var i = 0; i < 3; i++) {
        expect(toolResults[i].text, contains('[tool result truncated'));
      }
      // Last 2 should be intact (recent).
      for (var i = 3; i < 5; i++) {
        expect(toolResults[i].text, isNot(contains('[tool result truncated')));
      }
    });

    test('does not trim small tool results', () {
      final messages = [
        Message.user('Hi'),
        Message.user('Bye'), // second turn makes first one eligible
        Message.toolResult(
          callId: 'tc0',
          content: 'short', // below 200-token threshold
          toolName: 'tool',
        ),
      ];
      const trimmer = ToolResultTrimmer(keepRecentN: 1);
      final result = trimmer.trim(messages);
      final toolResult = result.firstWhere((m) => m.role == Role.toolResult);
      expect(toolResult.text, 'short');
    });

    test('preserves tool call id and tool name on trimmed result', () {
      final conv = _makeConversation(2);
      const trimmer = ToolResultTrimmer(keepRecentN: 1);
      final result = trimmer.trim(conv);
      final oldResult = result.firstWhere((m) => m.role == Role.toolResult);
      expect(oldResult.toolCallId, isNotNull);
      expect(oldResult.toolName, 'read_file');
    });

    test('keepRecentN override in trim() takes precedence', () {
      final conv = _makeConversation(4);
      const trimmer = ToolResultTrimmer(keepRecentN: 3);
      // Override to keep only 1 recent turn.
      final result = trimmer.trim(conv, keepRecentN: 1);
      final toolResults =
          result.where((m) => m.role == Role.toolResult).toList();
      // 3 should be truncated.
      expect(
        toolResults.where((m) => m.text!.contains('[tool result truncated')),
        hasLength(3),
      );
    });
  });
}
