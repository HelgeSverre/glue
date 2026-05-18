/// Tests that pin down the proposed sealed-type contract.
///
/// These tests intentionally exhaustively switch over [SessionEvent] and
/// [SessionCommand]. If a new variant is added without updating the
/// switch arms, the analyzer's exhaustiveness check turns this test into
/// a compile error — making "did we add a new event but forget to teach
/// consumers about it?" impossible to miss.
library;

import 'package:glue_core/glue_core.dart';
import 'package:test/test.dart';

void main() {
  group('SessionEvent identity', () {
    test('extension type IDs are zero-cost wrappers', () {
      const a = SessionId('abc');
      const b = SessionId('abc');
      expect(a, equals(b));
      expect(a.value, equals('abc'));
    });

    test('extension type wrappers preserve their value', () {
      const session = SessionId('x');
      const project = ProjectId('x');
      // The wrapped values compare equal, but the static types are
      // distinct — `void f(SessionId) {}; f(project);` would be a
      // compile error. That guarantee is what these wrappers buy us.
      expect(session.value, equals(project.value));
    });
  });

  group('SessionEvent exhaustiveness', () {
    test('switch covers every variant', () {
      // If a new variant is added to SessionEvent and not handled here,
      // this test will fail to compile.
      String name(SessionEvent e) => switch (e) {
            UserMessageEvent() => 'UserMessageEvent',
            AssistantThinkingStartedEvent() => 'AssistantThinkingStartedEvent',
            AssistantChunkEvent() => 'AssistantChunkEvent',
            AssistantMessageEvent() => 'AssistantMessageEvent',
            AssistantThinkingCompletedEvent() =>
              'AssistantThinkingCompletedEvent',
            ToolCallStartedEvent() => 'ToolCallStartedEvent',
            ToolCallProgressEvent() => 'ToolCallProgressEvent',
            ToolCallCompletedEvent() => 'ToolCallCompletedEvent',
            PermissionRequestedEvent() => 'PermissionRequestedEvent',
            PermissionResolvedEvent() => 'PermissionResolvedEvent',
            SubagentSpawnedEvent() => 'SubagentSpawnedEvent',
            SubagentEventForwardedEvent() => 'SubagentEventForwardedEvent',
            SubagentCompletedEvent() => 'SubagentCompletedEvent',
            DeviceCodeRequestedEvent() => 'DeviceCodeRequestedEvent',
            DeviceCodeResolvedEvent() => 'DeviceCodeResolvedEvent',
            TurnStartedEvent() => 'TurnStartedEvent',
            TurnCompletedEvent() => 'TurnCompletedEvent',
            StatusChangeEvent() => 'StatusChangeEvent',
            TitleGeneratedEvent() => 'TitleGeneratedEvent',
            MetricsUpdatedEvent() => 'MetricsUpdatedEvent',
            ErrorEvent() => 'ErrorEvent',
            McpServerConnectedEvent() => 'McpServerConnectedEvent',
            McpServerDisconnectedEvent() => 'McpServerDisconnectedEvent',
            McpServerErrorEvent() => 'McpServerErrorEvent',
            McpServerAuthRequiredEvent() => 'McpServerAuthRequiredEvent',
            McpToolListChangedEvent() => 'McpToolListChangedEvent',
            RuntimeCommandStartedEvent() => 'RuntimeCommandStartedEvent',
            RuntimeCommandOutputEvent() => 'RuntimeCommandOutputEvent',
            RuntimeCommandCompletedEvent() => 'RuntimeCommandCompletedEvent',
            RuntimeCommandFailedEvent() => 'RuntimeCommandFailedEvent',
            RuntimeCommandCancelledEvent() => 'RuntimeCommandCancelledEvent',
            RuntimeContainerStartedEvent() => 'RuntimeContainerStartedEvent',
            RuntimeContainerStoppedEvent() => 'RuntimeContainerStoppedEvent',
          };

      const turn = TurnId('t1');
      final ts = DateTime(2026);
      const usage = TokenUsage(promptTokens: 1, completionTokens: 1);
      final event = TurnStartedEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 0,
        model: const ModelRef(
          providerId: 'anthropic',
          modelId: 'claude-opus-4-7',
        ),
      );
      expect(name(event), equals('TurnStartedEvent'));

      final completed = TurnCompletedEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 1,
        outcome: TurnOutcome.completed,
        usage: usage,
      );
      expect(name(completed), equals('TurnCompletedEvent'));
    });

    test('runtime command lifecycle variants carry the expected fields', () {
      const turn = TurnId('t');
      final ts = DateTime(2026);

      final started = RuntimeCommandStartedEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 0,
        runtimeId: 'daytona',
        commandId: 'c-1',
        command: 'ls /workspace',
        runtimeCwd: '/workspace',
        sessionScopedId: 'sb-abc',
      );
      expect(started.runtimeId, 'daytona');
      expect(started.commandId, 'c-1');
      expect(started.command, 'ls /workspace');
      expect(started.runtimeCwd, '/workspace');
      expect(started.sessionScopedId, 'sb-abc');

      final output = RuntimeCommandOutputEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 1,
        commandId: 'c-1',
        stream: RuntimeOutputStream.stdout,
        text: 'pubspec.yaml\n',
      );
      expect(output.stream, RuntimeOutputStream.stdout);

      final completed = RuntimeCommandCompletedEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 2,
        commandId: 'c-1',
        exitCode: 0,
        duration: const Duration(milliseconds: 42),
      );
      expect(completed.exitCode, 0);
      expect(completed.duration, const Duration(milliseconds: 42));

      final failed = RuntimeCommandFailedEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 3,
        commandId: 'c-2',
        errorType: 'HttpException',
        message: 'connection reset',
      );
      expect(failed.errorType, 'HttpException');

      final cancelled = RuntimeCommandCancelledEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 4,
        commandId: 'c-3',
        reason: RuntimeCancelReason.userCancelled,
      );
      expect(cancelled.reason, RuntimeCancelReason.userCancelled);
    });

    test('runtime container lifecycle variants carry expected fields', () {
      const turn = TurnId('t');
      final ts = DateTime(2026);

      final started = RuntimeContainerStartedEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 0,
        runtimeId: 'docker',
        containerId: 'abc123',
        image: 'ubuntu:24.04',
      );
      expect(started.image, 'ubuntu:24.04');

      final stopped = RuntimeContainerStoppedEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 1,
        runtimeId: 'docker',
        containerId: 'abc123',
        reason: RuntimeContainerStopReason.sessionEnded,
      );
      expect(stopped.reason, RuntimeContainerStopReason.sessionEnded);
    });

    test('sequence numbers establish ordering', () {
      const turn = TurnId('t');
      final ts = DateTime(2026);
      final events = <SessionEvent>[
        UserMessageEvent(
          turnId: turn,
          timestamp: ts,
          sequence: 0,
          text: 'hi',
        ),
        TurnStartedEvent(
          turnId: turn,
          timestamp: ts,
          sequence: 1,
          model: const ModelRef(providerId: 'p', modelId: 'm'),
        ),
        AssistantChunkEvent(
          turnId: turn,
          timestamp: ts,
          sequence: 2,
          delta: 'hello',
          kind: ChunkKind.text,
        ),
      ];
      final sorted = [...events]
        ..sort((a, b) => a.sequence.compareTo(b.sequence));
      expect(sorted.map((e) => e.sequence), orderedEquals([0, 1, 2]));
    });
  });

  group('SessionCommand exhaustiveness', () {
    test('switch covers every variant', () {
      String name(SessionCommand c) => switch (c) {
            SendMessageCommand() => 'SendMessageCommand',
            InterruptCommand() => 'InterruptCommand',
            CancelCommand() => 'CancelCommand',
            ResolvePermissionCommand() => 'ResolvePermissionCommand',
            ResolveDeviceCodeCommand() => 'ResolveDeviceCodeCommand',
            SwitchModelCommand() => 'SwitchModelCommand',
            RegenerateCommand() => 'RegenerateCommand',
          };

      expect(name(const InterruptCommand()), equals('InterruptCommand'));
      expect(name(const CancelCommand()), equals('CancelCommand'));
      expect(
        name(const SendMessageCommand(text: 'hi')),
        equals('SendMessageCommand'),
      );
    });
  });

  group('ToolResultSnapshot exhaustiveness', () {
    test('switch covers every variant', () {
      String name(ToolResultSnapshot r) => switch (r) {
            ToolOkSnapshot() => 'ok',
            ToolErrorSnapshot() => 'error',
            ToolCancelledSnapshot() => 'cancelled',
          };

      const id = ToolCallId('t');
      const elapsed = Duration.zero;
      expect(
        name(
            const ToolOkSnapshot(id: id, elapsed: elapsed, contentSummary: '')),
        equals('ok'),
      );
      expect(
        name(const ToolCancelledSnapshot(id: id, elapsed: elapsed)),
        equals('cancelled'),
      );
      expect(
        name(const ToolErrorSnapshot(
          id: id,
          elapsed: elapsed,
          message: '',
          category: ErrorCategory.tool,
          retryable: false,
        )),
        equals('error'),
      );
    });
  });

  group('SubagentEventForwardedEvent', () {
    test('carries an inner event recursively', () {
      const turn = TurnId('parent');
      const childTurn = TurnId('child');
      final ts = DateTime(2026);
      final inner = AssistantChunkEvent(
        turnId: childTurn,
        timestamp: ts,
        sequence: 0,
        delta: 'x',
        kind: ChunkKind.text,
      );
      final forwarded = SubagentEventForwardedEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 5,
        childId: const SubagentId('sub'),
        inner: inner,
      );

      expect(forwarded.inner, same(inner));
      expect(forwarded.inner, isA<AssistantChunkEvent>());
    });
  });
}
