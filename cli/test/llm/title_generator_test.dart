import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/llm/title_generator.dart';
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
  group('TitleGenerator.generate', () {
    test('returns title from streamed text chunks', () async {
      final llm = _FakeLlmClient(chunks: [
        TextDelta('Fix'),
        TextDelta(' auth'),
        TextDelta(' bug'),
      ]);
      final generator = TitleGenerator(llmClient: llm);

      final title = await generator.generate('The login is broken');

      expect(title, 'Fix auth bug');
      expect(llm.lastMessages, isNotNull);
      expect(llm.lastMessages!.length, 1);
      expect(llm.lastMessages!.single.role, Role.user);
      expect(llm.lastMessages!.single.text, contains('<message>'));
    });

    test('returns null on stream exception', () async {
      final llm = _FakeLlmClient(error: Exception('network error'));
      final generator = TitleGenerator(llmClient: llm);

      expect(await generator.generate('test'), isNull);
    });

    test('returns null when stream emits no text', () async {
      final llm = _FakeLlmClient(chunks: const []);
      final generator = TitleGenerator(llmClient: llm);

      expect(await generator.generate('test'), isNull);
    });
  });

  group('TitleGenerator.sanitize', () {
    test('passes through clean ASCII text', () {
      expect(TitleGenerator.sanitize('Fix auth bug'), 'Fix auth bug');
    });

    test('strips emoji', () {
      expect(TitleGenerator.sanitize('Fix auth bug \u{1F41B}'), 'Fix auth bug');
    });

    test('strips zalgo combining marks', () {
      expect(
        TitleGenerator.sanitize('F\u0300\u0301ix auth'),
        'Fix auth',
      );
    });

    test('collapses whitespace', () {
      expect(TitleGenerator.sanitize('Fix   auth   bug'), 'Fix auth bug');
    });

    test('returns null for empty input', () {
      expect(TitleGenerator.sanitize(''), isNull);
    });

    test('returns null for null input', () {
      expect(TitleGenerator.sanitize(null), isNull);
    });

    test('returns null when only non-ASCII remains', () {
      expect(TitleGenerator.sanitize('\u{1F600}\u{1F601}'), isNull);
    });

    test('truncates to 60 chars', () {
      final long = 'A' * 100;
      final result = TitleGenerator.sanitize(long);
      expect(result!.length, 60);
    });

    test('trims leading and trailing whitespace', () {
      expect(TitleGenerator.sanitize('  Fix bug  '), 'Fix bug');
    });
  });
}
