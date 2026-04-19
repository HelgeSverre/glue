import 'package:glue/src/providers/auth_flow.dart';
import 'package:test/test.dart';

void main() {
  group('AuthFlow (sealed)', () {
    test('ApiKeyFlow holds prefill + help metadata', () {
      const flow = ApiKeyFlow(
        providerId: 'anthropic',
        providerName: 'Anthropic',
        envVar: 'ANTHROPIC_API_KEY',
        envPresent: 'sk-env-value',
        helpUrl: 'https://console.anthropic.com/settings/keys',
      );
      expect(flow.providerId, 'anthropic');
      expect(flow.envPresent, 'sk-env-value');
      expect(flow.helpUrl, contains('anthropic.com'));
    });

    test('DeviceCodeFlow exposes user-facing code + poll metadata', () {
      final expires = DateTime.utc(2026, 4, 19, 13, 0);
      final flow = DeviceCodeFlow(
        providerId: 'copilot',
        providerName: 'GitHub Copilot',
        verificationUri: 'https://github.com/login/device',
        userCode: 'ABCD-1234',
        pollInterval: const Duration(seconds: 5),
        expiresAt: expires,
        progress: const Stream.empty(),
      );
      expect(flow.userCode, 'ABCD-1234');
      expect(flow.verificationUri, contains('login/device'));
      expect(flow.expiresAt, expires);
    });

    test('pattern matching on AuthFlow variants is exhaustive', () {
      final flows = <AuthFlow>[
        const ApiKeyFlow(providerId: 'x', providerName: 'X'),
        DeviceCodeFlow(
          providerId: 'y',
          providerName: 'Y',
          verificationUri: 'https://example/device',
          userCode: 'ABCD',
          pollInterval: const Duration(seconds: 1),
          expiresAt: DateTime.now().add(const Duration(minutes: 10)),
          progress: const Stream.empty(),
        ),
        const PkceFlow(
          providerId: 'z',
          providerName: 'Z',
          authUrl: 'https://example/auth',
          state: 'abc',
          redirectPort: 51234,
        ),
      ];
      for (final f in flows) {
        final label = switch (f) {
          ApiKeyFlow() => 'api_key',
          DeviceCodeFlow() => 'device_code',
          PkceFlow() => 'pkce',
        };
        expect(label, isNotEmpty);
      }
    });
  });

  group('AuthFlowProgress', () {
    test('destructures Succeeded with stored fields', () {
      const progress = AuthFlowSucceeded(fields: {'github_token': 'gho_x'});
      expect(progress.fields['github_token'], 'gho_x');
    });

    test('destructures Failed with a reason', () {
      const progress = AuthFlowFailed(reason: 'user denied');
      expect(progress.reason, 'user denied');
    });

    test('pattern matching on AuthFlowProgress is exhaustive', () {
      final events = <AuthFlowProgress>[
        const AuthFlowPolling(),
        const AuthFlowSucceeded(fields: {'k': 'v'}),
        const AuthFlowFailed(reason: 'timeout'),
      ];
      for (final e in events) {
        final label = switch (e) {
          AuthFlowPolling() => 'polling',
          AuthFlowSucceeded() => 'succeeded',
          AuthFlowFailed() => 'failed',
        };
        expect(label, isNotEmpty);
      }
    });
  });
}
