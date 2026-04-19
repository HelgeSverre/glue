import 'package:glue/src/credentials/credential_ref.dart';
import 'package:test/test.dart';

void main() {
  group('CredentialRef', () {
    test('sealed variants can be destructured via pattern matching', () {
      const CredentialRef ref = EnvCredential('ANTHROPIC_API_KEY');
      final description = switch (ref) {
        EnvCredential(:final name) => 'env:$name',
        StoredCredential(:final key) => 'stored:$key',
        InlineCredential() => 'inline',
        NoCredential() => 'none',
      };
      expect(description, 'env:ANTHROPIC_API_KEY');
    });

    test('equality is structural for Env and Stored', () {
      expect(const EnvCredential('X'), equals(const EnvCredential('X')));
      expect(const EnvCredential('X'), isNot(equals(const EnvCredential('Y'))));
      expect(const StoredCredential('a'), equals(const StoredCredential('a')));
    });

    test('NoCredential is a singleton-like value', () {
      expect(const NoCredential(), equals(const NoCredential()));
    });

    test('InlineCredential equality includes the value', () {
      expect(
          const InlineCredential('k1'), equals(const InlineCredential('k1')));
      expect(
        const InlineCredential('k1'),
        isNot(equals(const InlineCredential('k2'))),
      );
    });
  });
}
