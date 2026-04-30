import 'package:glue_core/glue_core.dart';
import 'package:glue_server/glue_server.dart';
import 'package:test/test.dart';

void main() {
  const turn = TurnId('t1');
  final ts = DateTime(2026);

  group('sessionEventToAcpUpdate', () {
    test('AssistantChunkEvent (text) becomes agent_message_chunk', () {
      final event = AssistantChunkEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 0,
        delta: 'hello',
        kind: ChunkKind.text,
      );
      final upd = sessionEventToAcpUpdate(event);
      expect(upd, isA<AgentMessageChunkUpdate>());
      expect((upd! as AgentMessageChunkUpdate).text, 'hello');
      expect(upd.toJson(), {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'hello'},
      });
    });

    test('AssistantChunkEvent (thinking) becomes agent_thought_chunk', () {
      final event = AssistantChunkEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 0,
        delta: 'pondering',
        kind: ChunkKind.thinking,
      );
      final upd = sessionEventToAcpUpdate(event);
      expect(upd, isA<AgentThoughtChunkUpdate>());
    });

    test('ToolCallStartedEvent maps tool kinds correctly', () {
      ToolCallKind mapKind(ToolKind k) {
        final event = ToolCallStartedEvent(
          turnId: turn,
          timestamp: ts,
          sequence: 0,
          id: const ToolCallId('tc'),
          tool: 'name',
          args: const {},
          kind: k,
        );
        return (sessionEventToAcpUpdate(event)! as ToolCallUpdate).kind_;
      }

      expect(mapKind(ToolKind.read), ToolCallKind.read);
      expect(mapKind(ToolKind.write), ToolCallKind.edit);
      expect(mapKind(ToolKind.exec), ToolCallKind.execute);
      expect(mapKind(ToolKind.network), ToolCallKind.fetch);
      expect(mapKind(ToolKind.meta), ToolCallKind.other);
    });

    test('ToolCallStartedEvent emits in_progress status with rawInput', () {
      final event = ToolCallStartedEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 0,
        id: const ToolCallId('tc-1'),
        tool: 'read_file',
        args: const {'path': 'a.txt'},
        kind: ToolKind.read,
      );
      final upd = sessionEventToAcpUpdate(event)! as ToolCallUpdate;
      expect(upd.toolCallId, 'tc-1');
      expect(upd.title, 'read_file');
      expect(upd.status, ToolCallStatus.inProgress);
      expect(upd.rawInput, {'path': 'a.txt'});
    });

    test('ToolCallCompletedEvent (ok) → completed', () {
      final event = ToolCallCompletedEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 0,
        id: const ToolCallId('tc'),
        result: const ToolOkSnapshot(
          id: ToolCallId('tc'),
          elapsed: Duration(milliseconds: 5),
          contentSummary: 'Read foo.dart (42 lines)',
        ),
        elapsed: const Duration(milliseconds: 5),
      );
      final upd = sessionEventToAcpUpdate(event)! as ToolCallStatusUpdate;
      expect(upd.status, ToolCallStatus.completed);
      expect(upd.content.first, isA<AcpToolCallContentValue>());
      final block = (upd.content.first as AcpToolCallContentValue).block;
      expect(block, isA<AcpTextBlock>());
      expect((block as AcpTextBlock).text, 'Read foo.dart (42 lines)');
    });

    test('ToolCallCompletedEvent (error) → failed', () {
      final event = ToolCallCompletedEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 0,
        id: const ToolCallId('tc'),
        result: const ToolErrorSnapshot(
          id: ToolCallId('tc'),
          elapsed: Duration.zero,
          message: 'denied',
          category: ErrorCategory.tool,
          retryable: false,
        ),
        elapsed: Duration.zero,
      );
      final upd = sessionEventToAcpUpdate(event)! as ToolCallStatusUpdate;
      expect(upd.status, ToolCallStatus.failed);
    });

    test('ToolCallCompletedEvent (cancelled) → failed', () {
      final event = ToolCallCompletedEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 0,
        id: const ToolCallId('tc'),
        result: const ToolCancelledSnapshot(
          id: ToolCallId('tc'),
          elapsed: Duration.zero,
        ),
        elapsed: Duration.zero,
      );
      final upd = sessionEventToAcpUpdate(event)! as ToolCallStatusUpdate;
      expect(upd.status, ToolCallStatus.failed);
    });

    test('SubagentEventForwardedEvent recursively maps the inner event', () {
      final inner = AssistantChunkEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 0,
        delta: 'sub',
        kind: ChunkKind.text,
      );
      final forwarded = SubagentEventForwardedEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 1,
        childId: const SubagentId('child'),
        inner: inner,
      );
      final upd = sessionEventToAcpUpdate(forwarded);
      expect(upd, isA<AgentMessageChunkUpdate>());
      expect((upd! as AgentMessageChunkUpdate).text, 'sub');
    });

    test('AcpContentBlock.fromContentPart preserves all variants', () {
      final text = AcpContentBlock.fromContentPart(const TextPart('hi'));
      expect(text, isA<AcpTextBlock>());
      expect((text as AcpTextBlock).text, 'hi');

      final image = AcpContentBlock.fromContentPart(
        const ImagePart(bytes: [1, 2, 3], mimeType: 'image/png'),
      );
      expect(image, isA<AcpImageBlock>());
      expect((image as AcpImageBlock).mimeType, 'image/png');

      final link = AcpContentBlock.fromContentPart(
        const ResourceLinkPart(
          uri: 'https://example.com/x.html',
          name: 'Example',
          description: 'an example page',
          mimeType: 'text/html',
        ),
      );
      expect(link, isA<AcpResourceLinkBlock>());
      final wire = (link as AcpResourceLinkBlock).toJson();
      expect(wire, {
        'type': 'resource_link',
        'uri': 'https://example.com/x.html',
        'name': 'Example',
        'description': 'an example page',
        'mimeType': 'text/html',
      });
    });

    test('AcpResourceLinkBlock round-trips through fromJson', () {
      const original = AcpResourceLinkBlock(
        uri: 'https://example.com/',
        name: 'Example',
      );
      final back = AcpContentBlock.fromJson(original.toJson());
      expect(back, isA<AcpResourceLinkBlock>());
      expect((back as AcpResourceLinkBlock).uri, original.uri);
      expect(back.name, original.name);
    });

    test('out-of-band events return null', () {
      final permission = PermissionRequestedEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 0,
        requestId: const PermissionRequestId('r'),
        toolCallId: const ToolCallId('tc'),
        scope: PermissionScope.singleCall,
        summary: 'rm -rf /',
        dangerLevel: ToolKind.exec,
      );
      expect(sessionEventToAcpUpdate(permission), isNull);

      final deviceCode = DeviceCodeRequestedEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 0,
        code: 'ABCD',
        verificationUrl: 'https://x',
        expiresIn: const Duration(minutes: 15),
      );
      expect(sessionEventToAcpUpdate(deviceCode), isNull);

      final turnDone = TurnCompletedEvent(
        turnId: turn,
        timestamp: ts,
        sequence: 0,
        outcome: TurnOutcome.completed,
        usage: const TokenUsage(promptTokens: 0, completionTokens: 0),
      );
      expect(sessionEventToAcpUpdate(turnDone), isNull);
    });
  });
}
