/// Tests that pin down the proposed sealed-type contract.
///
/// These tests intentionally exhaustively switch over [SessionEvent] and
/// [SessionCommand]. If a new variant is added without updating the
/// switch arms, the analyzer's exhaustiveness check turns this test into
/// a compile error — making "did we add a new event but forget to teach
/// consumers about it?" impossible to miss.
library;

import 'package:glue/src/_proposed_core/proposed_core.dart';
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
          };

      const turn = TurnId('t1');
      final ts = DateTime(2026);
      const usage = TokenUsage(promptTokens: 1, completionTokens: 1);
      final event = TurnStartedEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 0,
        model: const ModelRef('anthropic/claude-opus-4-7'),
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
          model: const ModelRef('m'),
        ),
        AssistantChunkEvent(
          turnId: turn,
          timestamp: ts,
          sequence: 2,
          delta: 'hello',
          kind: ChunkKind.text,
        ),
      ];
      final sorted = [...events]..sort((a, b) => a.sequence.compareTo(b.sequence));
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
        name(const ToolOkSnapshot(id: id, elapsed: elapsed, contentSummary: '')),
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
