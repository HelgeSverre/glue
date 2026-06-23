import 'package:glue_core/glue_core.dart';
import 'package:test/test.dart';

class _AwareClient implements LlmClient, ContextWindowAware {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) =>
      const Stream.empty();

  @override
  int? get contextWindow => 4096;
}

class _PlainClient implements LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) =>
      const Stream.empty();
}

void main() {
  test('a ContextWindowAware client exposes its window', () {
    expect(_AwareClient().contextWindow, 4096);
  });

  test('a plain LlmClient is not ContextWindowAware (opt-in capability)', () {
    expect(_PlainClient(), isNot(isA<ContextWindowAware>()));
  });
}
