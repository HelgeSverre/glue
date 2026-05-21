import 'dart:math';

import 'package:glue_strategies/src/mcp_client/connection_state.dart';
import 'package:test/test.dart';

void main() {
  group('mcpBackoff', () {
    // Use a deterministic Random so the jitter term is predictable.
    final fixedRandom = Random(0);

    test('first attempt returns roughly the initial delay', () {
      final delay = mcpBackoff(
        attempt: 1,
        initial: const Duration(milliseconds: 500),
        max: const Duration(seconds: 30),
        jitterFraction: 0.0,
      );
      expect(delay.inMilliseconds, 500);
    });

    test('doubles each attempt until clamped at max', () {
      final delays = [
        for (var i = 1; i <= 8; i++)
          mcpBackoff(
            attempt: i,
            initial: const Duration(milliseconds: 500),
            max: const Duration(seconds: 30),
            jitterFraction: 0.0,
          ).inMilliseconds,
      ];
      // 500, 1000, 2000, 4000, 8000, 16000, 30000, 30000
      expect(delays, [500, 1000, 2000, 4000, 8000, 16000, 30000, 30000]);
    });

    test('jitter only adds, never subtracts', () {
      for (var i = 0; i < 100; i++) {
        final delay = mcpBackoff(
          attempt: 3,
          initial: const Duration(milliseconds: 500),
          max: const Duration(seconds: 30),
          jitterFraction: 0.3,
          random: fixedRandom,
        );
        // Base for attempt 3 = 2000ms. Jitter ≤ 600ms.
        expect(delay.inMilliseconds, greaterThanOrEqualTo(2000));
        expect(delay.inMilliseconds, lessThanOrEqualTo(2600));
      }
    });

    test('very large attempts do not overflow', () {
      // Without the shift clamp, 1 << 100 would overflow.
      final delay = mcpBackoff(
        attempt: 100,
        initial: const Duration(milliseconds: 500),
        max: const Duration(seconds: 30),
        jitterFraction: 0.0,
      );
      expect(delay.inMilliseconds, 30000);
    });
  });

  group('McpConnectionState (sealed)', () {
    test('exhaustive switch compiles', () {
      String label(McpConnectionState s) => switch (s) {
        McpDisconnected() => 'disconnected',
        McpConnecting() => 'connecting',
        McpConnected() => 'connected',
        McpReconnecting() => 'reconnecting',
        McpDead() => 'dead',
      };
      expect(label(const McpDisconnected()), 'disconnected');
      expect(label(const McpConnecting(attempt: 1)), 'connecting');
      expect(
        label(
          McpConnected(
            connectedAt: DateTime(2026),
            serverName: 'srv',
            serverVersion: '1',
            protocolVersion: '2025-03-26',
          ),
        ),
        'connected',
      );
      expect(
        label(
          const McpReconnecting(
            attempt: 3,
            nextAttemptIn: Duration(seconds: 4),
          ),
        ),
        'reconnecting',
      );
      expect(label(const McpDead(reason: 'crash_loop')), 'dead');
    });
  });
}
