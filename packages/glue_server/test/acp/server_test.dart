import 'dart:async';
import 'dart:convert';

import 'package:glue_core/glue_core.dart';
import 'package:glue_server/glue_server.dart';
import 'package:test/test.dart';

class _MemorySink implements Sink<List<int>> {
  final List<int> buffer = [];
  @override
  void add(List<int> data) => buffer.addAll(data);
  @override
  void close() {}
}

/// Fake delegate that runs scripted [AgentEvent]s and answers any
/// permission gate decision the test installs.
class _FakeDelegate extends AcpServerDelegate {
  _FakeDelegate({required this.scripted});

  final List<AgentEvent> scripted;
  String? lastSessionId;
  String? lastUserMessage;
  bool cancelled = false;
  bool Function(ToolCall call)? permissionAnswer;

  @override
  Future<String> createSession(SessionNewParams params) async {
    return 'session-${params.cwd.hashCode}';
  }

  List<ContentPart> lastUserContentParts = const [];

  @override
  Stream<AgentEvent> prompt({
    required String sessionId,
    required String userMessage,
    required Future<bool> Function(ToolCall call) requestPermission,
    List<ContentPart> userContentParts = const [],
  }) async* {
    lastSessionId = sessionId;
    lastUserMessage = userMessage;
    lastUserContentParts = userContentParts;
    for (final event in scripted) {
      if (event is AgentToolCall && permissionAnswer != null) {
        final granted = await requestPermission(event.call);
        if (!granted) continue;
      }
      yield event;
    }
  }

  @override
  void cancelPrompt(String sessionId) {
    cancelled = true;
  }

  /// Tests can override this to script per-session usage; the default
  /// returns an empty report so unrelated tests don't have to care.
  UsageReport Function(String sessionId)? usageSummaryAnswer;

  @override
  UsageReport usageSummary(String sessionId) =>
      usageSummaryAnswer?.call(sessionId) ??
      buildUsageReport(usageEvents: const [], sessionId: sessionId);

  @override
  Future<void> closeSession(String sessionId) async {}
}

void main() {
  group('AcpServer', () {
    late StreamController<List<int>> input;
    // ignore: close_sinks — _MemorySink is closed by the transport in serve().
    late _MemorySink output;
    late LineDelimitedTransport transport;

    setUp(() {
      input = StreamController<List<int>>();
      output = _MemorySink();
      transport = LineDelimitedTransport(input: input.stream, output: output);
    });

    tearDown(() async {
      if (!input.isClosed) await input.close();
      // ignore: close_sinks — output is a Sink<List<int>>; not a stream owner.
    });

    Future<List<Map<String, Object?>>> readSent() async {
      final lines = const LineSplitter().convert(utf8.decode(output.buffer));
      return [
        for (final l in lines)
          if (l.isNotEmpty) (jsonDecode(l) as Map).cast<String, Object?>(),
      ];
    }

    test('initialize → returns agentInfo + protocolVersion', () async {
      final delegate = _FakeDelegate(scripted: const []);
      final server = AcpServer(transport: transport, delegate: delegate);
      final serverFuture = server.serve();

      input.add(utf8.encode(
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":'
        '{"protocolVersion":1}}\n',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await input.close();
      await serverFuture;

      final sent = await readSent();
      expect(sent, hasLength(1));
      expect(sent.single['id'], 1);
      final result = sent.single['result']! as Map<String, Object?>;
      expect(result['protocolVersion'], 1);
      expect((result['agentInfo']! as Map)['name'], 'glue');
    });

    test('session/new → returns id from delegate', () async {
      final delegate = _FakeDelegate(scripted: const []);
      final server = AcpServer(transport: transport, delegate: delegate);
      final serverFuture = server.serve();

      input.add(utf8.encode(
        '{"jsonrpc":"2.0","id":1,"method":"session/new","params":'
        '{"cwd":"/tmp/abc"}}\n',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await input.close();
      await serverFuture;

      final sent = await readSent();
      expect(sent, hasLength(1));
      final result = sent.single['result']! as Map<String, Object?>;
      expect(result['sessionId'], isA<String>());
    });

    test('session/prompt streams text deltas + returns end_turn', () async {
      final delegate = _FakeDelegate(scripted: [
        AgentTextDelta('hello '),
        AgentTextDelta('world'),
        AgentDone(),
      ]);
      final server = AcpServer(transport: transport, delegate: delegate);
      final serverFuture = server.serve();

      input.add(utf8.encode(
        '{"jsonrpc":"2.0","id":1,"method":"session/new","params":'
        '{"cwd":"/tmp/p"}}\n',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      // Read the new sessionId.
      var sent = await readSent();
      final sessionId = (sent.single['result']! as Map)['sessionId'] as String;
      output.buffer.clear();

      const promptId = 7;
      input.add(utf8.encode(
        '{"jsonrpc":"2.0","id":$promptId,"method":"session/prompt","params":'
        '{"sessionId":"$sessionId","prompt":[{"type":"text","text":"hi"}]}}\n',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await input.close();
      await serverFuture;

      sent = await readSent();
      // Should contain 2 chunk notifications + 1 prompt response.
      final chunks = sent
          .where((m) => m['method'] == 'session/update')
          .map((m) => ((m['params']! as Map)['update']! as Map)['content']
              as Map<Object?, Object?>?)
          .whereType<Map<Object?, Object?>>()
          .toList();
      expect(chunks.map((c) => c['text']).toList(), ['hello ', 'world']);

      final response = sent.firstWhere((m) => m['id'] == promptId);
      expect(
        (response['result']! as Map)['stopReason'],
        'end_turn',
      );
      expect(delegate.lastUserMessage, 'hi');
      expect(delegate.lastSessionId, sessionId);
    });

    test('session/prompt → unknown sessionId returns sessionNotFound',
        () async {
      final delegate = _FakeDelegate(scripted: const []);
      final server = AcpServer(transport: transport, delegate: delegate);
      final serverFuture = server.serve();

      input.add(utf8.encode(
        '{"jsonrpc":"2.0","id":9,"method":"session/prompt","params":'
        '{"sessionId":"nope","prompt":[{"type":"text","text":"x"}]}}\n',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await input.close();
      await serverFuture;

      final sent = await readSent();
      expect(sent.single['error']! as Map, contains('code'));
      expect(((sent.single['error']! as Map)['code'] as num).toInt(), -32001);
    });

    test('session/usage_summary returns the delegate report as JSON',
        () async {
      final delegate = _FakeDelegate(scripted: const []);
      delegate.usageSummaryAnswer = (sessionId) => buildUsageReport(
            sessionId: sessionId,
            modelLabel: 'anthropic/claude-sonnet-4.6',
            usageEvents: [
              {
                'type': 'usage',
                'role': 'main',
                'input_tokens': 1000,
                'output_tokens': 500,
                'cache_read_tokens': 8000,
                'cache_creation_tokens': 1500,
                'turn_count': 3,
              },
            ],
          );
      final server = AcpServer(transport: transport, delegate: delegate);
      final serverFuture = server.serve();

      input.add(utf8.encode(
        '{"jsonrpc":"2.0","id":1,"method":"session/new","params":'
        '{"cwd":"/tmp/p"}}\n',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      var sent = await readSent();
      final sessionId = (sent.single['result']! as Map)['sessionId'] as String;
      output.buffer.clear();

      input.add(utf8.encode(
        '{"jsonrpc":"2.0","id":42,"method":"session/usage_summary","params":'
        '{"sessionId":"$sessionId"}}\n',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await input.close();
      await serverFuture;

      sent = await readSent();
      final response = sent.singleWhere((m) => m['id'] == 42);
      final result = response['result']! as Map<Object?, Object?>;
      expect(result['model'], 'anthropic/claude-sonnet-4.6');
      expect(result['session_id'], sessionId);
      final totals = result['totals']! as Map<Object?, Object?>;
      expect(totals['calls'], 3);
      expect(totals['input_tokens'], 1000);
      expect(totals['output_tokens'], 500);
      expect(totals['cache_read_tokens'], 8000);
      expect(totals['cache_creation_tokens'], 1500);
      expect(totals['total_tokens'], 11000);
      // 8000 / (1000 + 8000)
      expect(totals['cache_hit_rate'], closeTo(8 / 9, 1e-9));
      final byRole = result['by_role']! as List;
      expect(byRole, hasLength(1));
      expect((byRole.single as Map)['role'], 'main');
    });

    test('session/usage_summary on unknown session returns sessionNotFound',
        () async {
      final delegate = _FakeDelegate(scripted: const []);
      final server = AcpServer(transport: transport, delegate: delegate);
      final serverFuture = server.serve();

      input.add(utf8.encode(
        '{"jsonrpc":"2.0","id":1,"method":"session/usage_summary","params":'
        '{"sessionId":"never-created"}}\n',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await input.close();
      await serverFuture;

      final sent = await readSent();
      expect(sent.single['error'], isNotNull);
      // sessionNotFound is -32001 in the existing JsonRpcErrorCode enum.
      expect(((sent.single['error']! as Map)['code'] as num).toInt(), -32001);
    });

    test('session/cancel notification reaches the delegate', () async {
      final delegate = _FakeDelegate(scripted: const []);
      final server = AcpServer(transport: transport, delegate: delegate);
      final serverFuture = server.serve();

      input.add(utf8.encode(
        '{"jsonrpc":"2.0","id":1,"method":"session/new","params":'
        '{"cwd":"/tmp/p"}}\n',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final sent = await readSent();
      final sessionId = (sent.single['result']! as Map)['sessionId'] as String;

      input.add(utf8.encode(
        '{"jsonrpc":"2.0","method":"session/cancel","params":'
        '{"sessionId":"$sessionId"}}\n',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await input.close();
      await serverFuture;

      expect(delegate.cancelled, isTrue);
    });

    test('session/prompt with image block forwards ImagePart to delegate',
        () async {
      final delegate = _FakeDelegate(scripted: [AgentDone()]);
      final server = AcpServer(transport: transport, delegate: delegate);
      final serverFuture = server.serve();

      input.add(utf8.encode(
        '{"jsonrpc":"2.0","id":1,"method":"session/new","params":'
        '{"cwd":"/tmp/p"}}\n',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final newRespLines = await readSent();
      final sessionId =
          (newRespLines.single['result']! as Map)['sessionId'] as String;
      output.buffer.clear();

      // Tiny PNG-ish bytes encoded as base64 (just for the test).
      final base64 = base64Encode([0x89, 0x50, 0x4e, 0x47, 0x0d]);
      final promptJson = jsonEncode({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'session/prompt',
        'params': {
          'sessionId': sessionId,
          'prompt': [
            {'type': 'text', 'text': 'what does this look like?'},
            {'type': 'image', 'mimeType': 'image/png', 'data': base64},
          ],
        },
      });
      input.add(utf8.encode('$promptJson\n'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await input.close();
      await serverFuture;

      expect(delegate.lastUserMessage, 'what does this look like?');
      expect(delegate.lastUserContentParts, hasLength(1));
      final part = delegate.lastUserContentParts.single;
      expect(part, isA<ImagePart>());
      expect((part as ImagePart).mimeType, 'image/png');
      expect(part.bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d]);
    });

    test('tool result with diff metadata surfaces as diff content block',
        () async {
      final call = ToolCall(
        id: const ToolCallId('tc-edit'),
        name: 'write_file',
        arguments: const {'path': '/tmp/x.txt', 'content': 'new'},
      );
      final delegate = _FakeDelegate(scripted: [
        AgentToolCallPending(id: call.id, name: call.name),
        AgentToolCall(call),
        AgentToolResult(ToolResult(
          callId: call.id,
          content: 'Wrote 3 bytes to /tmp/x.txt',
          summary: 'Wrote /tmp/x.txt',
          metadata: const {
            'path': '/tmp/x.txt',
            'diff': {
              'path': '/tmp/x.txt',
              'old_text': 'old\n',
              'new_text': 'new',
            },
          },
        )),
        AgentDone(),
      ]);
      final server = AcpServer(transport: transport, delegate: delegate);
      final serverFuture = server.serve();

      input.add(utf8.encode(
        '{"jsonrpc":"2.0","id":1,"method":"session/new","params":'
        '{"cwd":"/tmp/p"}}\n',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      var sent = await readSent();
      final sessionId = (sent.single['result']! as Map)['sessionId'] as String;
      output.buffer.clear();

      input.add(utf8.encode(
        '{"jsonrpc":"2.0","id":2,"method":"session/prompt","params":'
        '{"sessionId":"$sessionId","prompt":[{"type":"text","text":"go"}]}}\n',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await input.close();
      await serverFuture;

      sent = await readSent();
      final completed = sent
          .where((m) => m['method'] == 'session/update')
          .map((m) => (m['params']! as Map)['update'] as Map)
          .firstWhere(
            (u) => u['status'] == 'completed',
            orElse: () => fail('expected a completed tool_call_update'),
          );
      final content = completed['content']! as List;
      // The diff block is emitted first; nothing else (no contentParts).
      expect(content, hasLength(1));
      final diff = content.first as Map;
      expect(diff['type'], 'diff');
      expect(diff['path'], '/tmp/x.txt');
      expect(diff['oldText'], 'old\n');
      expect(diff['newText'], 'new');
    });

    test('tool result with ImagePart surfaces as image content block',
        () async {
      final call = ToolCall(
        id: const ToolCallId('tc-img'),
        name: 'web_browser',
        arguments: const {'action': 'screenshot'},
      );
      final delegate = _FakeDelegate(scripted: [
        AgentToolCallPending(id: call.id, name: call.name),
        AgentToolCall(call),
        AgentToolResult(ToolResult(
          callId: call.id,
          content: 'Screenshot captured.',
          summary: 'web_browser: screenshot of example.com',
          contentParts: const [
            TextPart('Screenshot of example.com'),
            ImagePart(bytes: [0x89, 0x50, 0x4e, 0x47], mimeType: 'image/png'),
          ],
        )),
        AgentDone(),
      ]);
      final server = AcpServer(transport: transport, delegate: delegate);
      final serverFuture = server.serve();

      input.add(utf8.encode(
        '{"jsonrpc":"2.0","id":1,"method":"session/new","params":'
        '{"cwd":"/tmp/p"}}\n',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      var sent = await readSent();
      final sessionId = (sent.single['result']! as Map)['sessionId'] as String;
      output.buffer.clear();

      input.add(utf8.encode(
        '{"jsonrpc":"2.0","id":2,"method":"session/prompt","params":'
        '{"sessionId":"$sessionId","prompt":[{"type":"text","text":"go"}]}}\n',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await input.close();
      await serverFuture;

      sent = await readSent();
      final completedUpdate = sent
          .where((m) => m['method'] == 'session/update')
          .map((m) => (m['params']! as Map)['update'] as Map)
          .firstWhere(
            (u) => u['status'] == 'completed',
            orElse: () => fail('expected a completed tool_call_update'),
          );
      final content = completedUpdate['content']! as List;
      // Two entries: text + image.
      expect(content, hasLength(2));
      final imageEntry = content.firstWhere(
        (c) => ((c as Map)['content'] as Map?)?['type'] == 'image',
        orElse: () => fail('expected an image content block'),
      ) as Map;
      final imageBlock = imageEntry['content']! as Map;
      expect(imageBlock['mimeType'], 'image/png');
      expect(imageBlock['data'], isA<String>()); // base64
    });

    test('tool call → permission allow → tool runs to completion', () async {
      final call = ToolCall(
        id: const ToolCallId('tc-1'),
        name: 'bash',
        arguments: const {'command': 'ls'},
        description: 'list files',
      );
      final delegate = _FakeDelegate(scripted: [
        AgentToolCallPending(id: call.id, name: call.name),
        AgentToolCall(call),
        AgentToolResult(ToolResult(
          callId: call.id,
          content: 'file1\nfile2\n',
          summary: 'bash: ls (exit 0)',
        )),
        AgentDone(),
      ])
        ..permissionAnswer = (_) => true;
      final server = AcpServer(transport: transport, delegate: delegate);
      final serverFuture = server.serve();

      // Open session.
      input.add(utf8.encode(
        '{"jsonrpc":"2.0","id":1,"method":"session/new","params":'
        '{"cwd":"/tmp/p"}}\n',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final newRespLines = await readSent();
      final sessionId =
          (newRespLines.single['result']! as Map)['sessionId'] as String;
      output.buffer.clear();

      // Drive prompt; the server will issue session/request_permission
      // on the first tool call. We have to answer it to let the prompt
      // complete.
      input.add(utf8.encode(
        '{"jsonrpc":"2.0","id":2,"method":"session/prompt","params":'
        '{"sessionId":"$sessionId","prompt":[{"type":"text","text":"go"}]}}\n',
      ));

      // Wait for request_permission to be sent, then reply.
      Map<String, Object?>? permReq;
      final start = DateTime.now();
      while (permReq == null) {
        final pending = await readSent();
        permReq = pending.cast<Map<String, Object?>?>().firstWhere(
              (m) => m?['method'] == 'session/request_permission',
              orElse: () => null,
            );
        if (DateTime.now().difference(start).inSeconds > 2) {
          fail('timed out waiting for request_permission');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final permId = permReq['id']!;
      input.add(utf8.encode(
        '{"jsonrpc":"2.0","id":$permId,"result":{"outcome":'
        '{"outcome":"selected","optionId":"allow"}}}\n',
      ));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await input.close();
      await serverFuture;

      final all = await readSent();
      // We should have: tool_call (pending or in_progress), tool_call_update
      // (in_progress), tool_call_update (completed), prompt response.
      final toolUpdates = all
          .where((m) => m['method'] == 'session/update')
          .map((m) => (m['params']! as Map)['update'] as Map)
          .toList();
      final completeds = toolUpdates
          .where((u) =>
              u['sessionUpdate'] == 'tool_call_update' &&
              u['status'] == 'completed')
          .toList();
      expect(completeds, isNotEmpty);
    });
  });
}
