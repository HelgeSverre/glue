import 'package:glue_harness/glue_harness.dart';
import 'package:test/test.dart';

class _FakeLlmClient implements LlmClient {
  final List<LlmChunk> chunks;
  final Object? error;
  List<Message>? lastMessages;

  _FakeLlmClient({
    this.chunks = const [],
    this.error,
  });

  @override
  Stream<LlmChunk> stream(
    List<Message> messages, {
    List<Tool>? tools,
  }) async* {
    lastMessages = messages;
    if (error != null) {
      throw error!;
    }
    for (final chunk in chunks) {
      yield chunk;
    }
  }
}

void main() {
  group('RecapGenerator.generateFromContext', () {
    test('returns recap text from streamed chunks', () async {
      final llm = _FakeLlmClient(chunks: [
        TextDelta('Investigated docker resume flake, '),
        TextDelta('then patched the executor fallback.'),
      ]);
      final generator = RecapGenerator(llmClient: llm);

      final recap = await generator.generateFromContext(const TitleContext(
        firstUserMessage: 'help debug this',
        latestUserMessage: 'it fails in docker only',
        firstAssistantMessage: 'I found a flaky resume test.',
        latestAssistantMessage: 'Docker resume handling was patched.',
        toolNames: ['read_file', 'run_shell_command'],
        cwdBasename: 'glue',
      ));

      expect(recap,
          'Investigated docker resume flake, then patched the executor fallback.');
      expect(llm.lastMessages, isNotNull);
      expect(llm.lastMessages!.single.text, contains('<first_user>'));
      expect(llm.lastMessages!.single.text, contains('<tools>'));
    });

    test('forwards UsageInfo chunks via onUsage', () async {
      final usage = UsageInfo(inputTokens: 12, outputTokens: 7);
      final llm = _FakeLlmClient(chunks: [
        TextDelta('Did the thing.'),
        usage,
      ]);
      final received = <UsageInfo>[];
      final generator = RecapGenerator(
        llmClient: llm,
        onUsage: received.add,
      );

      final recap = await generator.generateFromContext(
          const TitleContext(firstUserMessage: 'go'));

      expect(recap, 'Did the thing.');
      expect(received, hasLength(1));
      expect(received.single.inputTokens, 12);
      expect(received.single.outputTokens, 7);
    });

    test('returns null on stream exception', () async {
      final llm = _FakeLlmClient(error: Exception('network down'));
      final generator = RecapGenerator(llmClient: llm);

      expect(
        await generator.generateFromContext(
            const TitleContext(firstUserMessage: 'go')),
        isNull,
      );
    });

    test('returns null when stream emits no text', () async {
      final llm = _FakeLlmClient(chunks: const []);
      final generator = RecapGenerator(llmClient: llm);

      expect(
        await generator.generateFromContext(
            const TitleContext(firstUserMessage: 'go')),
        isNull,
      );
    });
  });

  group('RecapGenerator.sanitize', () {
    test('strips wrapping double quotes', () {
      expect(RecapGenerator.sanitize('"Did the thing."'), 'Did the thing.');
    });

    test('strips wrapping single quotes', () {
      expect(RecapGenerator.sanitize("'Did the thing.'"), 'Did the thing.');
    });

    test('strips emoji and collapses whitespace', () {
      expect(
        RecapGenerator.sanitize('Refactored\u{1F389}    auth   path.'),
        'Refactored auth path.',
      );
    });

    test('returns null for empty input', () {
      expect(RecapGenerator.sanitize(''), isNull);
    });

    test('truncates beyond max length with ellipsis', () {
      final long = 'A' * 250;
      final result = RecapGenerator.sanitize(long);
      expect(result, isNotNull);
      expect(result!.length, lessThanOrEqualTo(204));
      expect(result.endsWith('...'), isTrue);
    });

    test('keeps short ASCII text intact', () {
      expect(
        RecapGenerator.sanitize('Investigated X, then patched Y.'),
        'Investigated X, then patched Y.',
      );
    });
  });
}
