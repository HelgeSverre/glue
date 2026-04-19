import 'package:glue/src/providers/compatibility_profile.dart';
import 'package:test/test.dart';

void main() {
  group('CompatibilityProfile.fromString', () {
    test('maps known profile ids', () {
      expect(
          CompatibilityProfile.fromString('groq'), CompatibilityProfile.groq);
      expect(
        CompatibilityProfile.fromString('ollama'),
        CompatibilityProfile.ollama,
      );
      expect(
        CompatibilityProfile.fromString('openrouter'),
        CompatibilityProfile.openrouter,
      );
      expect(
          CompatibilityProfile.fromString('vllm'), CompatibilityProfile.vllm);
      expect(
        CompatibilityProfile.fromString('mistral'),
        CompatibilityProfile.mistral,
      );
      expect(
        CompatibilityProfile.fromString('openai'),
        CompatibilityProfile.openai,
      );
    });

    test('defaults to openai for unknown / null values', () {
      expect(
          CompatibilityProfile.fromString(null), CompatibilityProfile.openai);
      expect(
        CompatibilityProfile.fromString('unknown-vendor'),
        CompatibilityProfile.openai,
      );
    });
  });

  group('authHeaders', () {
    test('ollama sends no Authorization header (auth-less local server)', () {
      expect(CompatibilityProfile.ollama.authHeaders('ignored'), isEmpty);
    });

    test('openai/groq/openrouter/vllm/mistral use Bearer token', () {
      for (final p in [
        CompatibilityProfile.openai,
        CompatibilityProfile.groq,
        CompatibilityProfile.openrouter,
        CompatibilityProfile.vllm,
        CompatibilityProfile.mistral,
      ]) {
        expect(p.authHeaders('sk-x'), {'Authorization': 'Bearer sk-x'});
      }
    });
  });

  group('mutateBody', () {
    test('openai preserves stream_options.include_usage', () {
      final body = <String, dynamic>{
        'stream_options': {'include_usage': true},
      };
      CompatibilityProfile.openai.mutateBody(body);
      expect(body, containsPair('stream_options', anything));
    });

    test('groq strips stream_options (not supported)', () {
      final body = <String, dynamic>{
        'stream_options': {'include_usage': true},
      };
      CompatibilityProfile.groq.mutateBody(body);
      expect(body.containsKey('stream_options'), isFalse);
    });

    test('ollama strips stream_options', () {
      final body = <String, dynamic>{
        'stream_options': {'include_usage': true},
      };
      CompatibilityProfile.ollama.mutateBody(body);
      expect(body.containsKey('stream_options'), isFalse);
    });

    test('vllm strips stream_options and null tool_choice', () {
      final body = <String, dynamic>{
        'stream_options': {'include_usage': true},
        'tool_choice': null,
      };
      CompatibilityProfile.vllm.mutateBody(body);
      expect(body.containsKey('stream_options'), isFalse);
      expect(body.containsKey('tool_choice'), isFalse);
    });

    test('vllm preserves non-null tool_choice', () {
      final body = <String, dynamic>{'tool_choice': 'auto'};
      CompatibilityProfile.vllm.mutateBody(body);
      expect(body['tool_choice'], 'auto');
    });
  });
}
