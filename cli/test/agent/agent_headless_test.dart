import 'dart:async';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:test/test.dart';

/// Minimal LLM that returns text only (no tool calls).
class _TextOnlyLlm implements LlmClient {
  final String response;

  _TextOnlyLlm(this.response);

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    for (final word in response.split(' ')) {
      yield TextDelta('$word ');
    }
    yield UsageInfo(inputTokens: 10, outputTokens: 5);
  }
}

/// LLM that makes one tool call then responds.
class _ToolCallLlm implements LlmClient {
  int _callCount = 0;

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    _callCount++;
    if (_callCount == 1) {
      yield TextDelta('Let me check. ');
      yield ToolCallStart(id: 'tc1', name: 'list_directory');
      yield ToolCallComplete(ToolCall(
        id: 'tc1',
        name: 'list_directory',
        arguments: {'path': '.'},
      ));
      yield UsageInfo(inputTokens: 10, outputTokens: 10);
    } else {
      yield TextDelta('Found the files.');
      yield UsageInfo(inputTokens: 20, outputTokens: 10);
    }
  }
}

void main() {
  group('Agent.runHeadless', () {
    test('runs text-only response to completion', () async {
      final agent = Agent(
        llm: _TextOnlyLlm('Hello from the agent'),
        tools: {},
      );
      final result = await agent.runHeadless('Hi');
      expect(result, contains('Hello'));
    });

    test('auto-approves tool calls in headless mode', () async {
      final agent = Agent(
        llm: _ToolCallLlm(),
        tools: {'list_directory': ListDirectoryTool()},
      );
      final result = await agent.runHeadless('List files');
      expect(result, contains('Found the files'));
    });

    test('emits AgentToolCallPending before AgentToolCall', () async {
      final events = <AgentEvent>[];
      final agent = Agent(
        llm: _ToolCallLlm(),
        tools: {'list_directory': ListDirectoryTool()},
      );
      await agent.runHeadless('List files', onEvent: events.add);

      final pendingIdx = events.indexWhere((e) => e is AgentToolCallPending);
      final callIdx = events.indexWhere((e) => e is AgentToolCall);
      expect(pendingIdx, greaterThanOrEqualTo(0));
      expect(callIdx, greaterThan(pendingIdx));

      final pending = events[pendingIdx] as AgentToolCallPending;
      expect(pending.name, 'list_directory');
      expect(pending.id, 'tc1');
    });

    test('denies tool calls in denyAll mode', () async {
      final agent = Agent(
        llm: _ToolCallLlm(),
        tools: {'list_directory': ListDirectoryTool()},
      );
      final result = await agent.runHeadless(
        'List files',
        policy: ToolApprovalPolicy.denyAll,
      );
      // After denial, the LLM gets another turn and responds.
      expect(result, contains('Found the files'));
    });
  });

  group('Agent.ensureToolResultsComplete', () {
    test('injects synthetic tool_result for unmatched tool_use', () {
      final core = Agent(
        llm: _TextOnlyLlm('hi'),
        tools: {},
      );
      core.addMessage(Message.user('do something'));
      core.addMessage(Message.assistant(
        text: 'Sure',
        toolCalls: [
          ToolCall(id: 'tc1', name: 'write_file', arguments: {'path': 'a.txt'}),
        ],
      ));
      // No tool_result — simulates cancel mid-execution.

      core.ensureToolResultsComplete();

      final messages = core.conversation;
      expect(messages, hasLength(3));
      expect(messages.last.role, Role.toolResult);
      expect(messages.last.toolCallId, 'tc1');
      expect(messages.last.text, '[cancelled by user]');
    });

    test('does not duplicate tool_result that already exists', () {
      final core = Agent(
        llm: _TextOnlyLlm('hi'),
        tools: {},
      );
      core.addMessage(Message.user('do something'));
      core.addMessage(Message.assistant(
        text: 'Sure',
        toolCalls: [
          ToolCall(id: 'tc1', name: 'write_file', arguments: {}),
        ],
      ));
      core.addMessage(Message.toolResult(
        callId: 'tc1',
        content: 'done',
        toolName: 'write_file',
      ));

      core.ensureToolResultsComplete();

      final results =
          core.conversation.where((m) => m.role == Role.toolResult).toList();
      expect(results, hasLength(1));
      expect(results.first.text, 'done');
    });

    test('repairs only missing results in multi-tool call', () {
      final core = Agent(
        llm: _TextOnlyLlm('hi'),
        tools: {},
      );
      core.addMessage(Message.user('do two things'));
      core.addMessage(Message.assistant(
        text: 'Sure',
        toolCalls: [
          ToolCall(id: 'tc1', name: 'read_file', arguments: {}),
          ToolCall(id: 'tc2', name: 'write_file', arguments: {}),
        ],
      ));
      // Only tc1 got a result before cancel.
      core.addMessage(Message.toolResult(
        callId: 'tc1',
        content: 'file contents',
        toolName: 'read_file',
      ));

      core.ensureToolResultsComplete();

      final results =
          core.conversation.where((m) => m.role == Role.toolResult).toList();
      expect(results, hasLength(2));
      expect(results[0].toolCallId, 'tc1');
      expect(results[0].text, 'file contents');
      expect(results[1].toolCallId, 'tc2');
      expect(results[1].text, '[cancelled by user]');
    });

    test('no-op when conversation has no tool calls', () {
      final core = Agent(
        llm: _TextOnlyLlm('hi'),
        tools: {},
      );
      core.addMessage(Message.user('hello'));
      core.addMessage(Message.assistant(text: 'hi there'));

      core.ensureToolResultsComplete();

      expect(core.conversation, hasLength(2));
    });

    test('no-op on empty conversation', () {
      final core = Agent(
        llm: _TextOnlyLlm('hi'),
        tools: {},
      );

      core.ensureToolResultsComplete();

      expect(core.conversation, isEmpty);
    });
  });
}
