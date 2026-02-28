import 'package:test/test.dart';
import 'package:glue/src/web/browser/providers/docker_browser_provider.dart';

void main() {
  group('DockerBrowserProvider', () {
    test('has correct name', () {
      final provider = DockerBrowserProvider(
        image: 'browserless/chrome:latest',
        port: 3000,
        sessionId: 'test-session',
      );
      expect(provider.name, 'docker');
    });

    test('is always available', () {
      final provider = DockerBrowserProvider(
        image: 'browserless/chrome:latest',
        port: 3000,
        sessionId: 'test-session',
      );
      expect(provider.isAvailable, isTrue);
    });

    test('builds docker run args correctly', () {
      final provider = DockerBrowserProvider(
        image: 'browserless/chrome:latest',
        port: 3000,
        sessionId: 'abc-123',
      );
      final args = provider.buildDockerRunArgs();
      expect(args, contains('--label'));
      expect(args, contains('glue.session=abc-123'));
      expect(args, contains('-p'));
      expect(args.any((a) => a.contains(':3000')), isTrue);
      expect(args, contains('browserless/chrome:latest'));
    });

    test('computes WebSocket URL from port', () {
      final provider = DockerBrowserProvider(
        image: 'browserless/chrome:latest',
        port: 3000,
        sessionId: 'test',
      );
      final wsUrl = provider.buildWsUrl(3000);
      expect(wsUrl, 'ws://localhost:3000');
    });

    test('parseHostPort handles IPv4 format', () {
      expect(
        DockerBrowserProvider.parseHostPort('0.0.0.0:49152'),
        49152,
      );
    });

    test('parseHostPort handles IPv6 format', () {
      expect(
        DockerBrowserProvider.parseHostPort('[::]:49152'),
        49152,
      );
    });

    test('parseHostPort handles localhost format', () {
      expect(
        DockerBrowserProvider.parseHostPort('127.0.0.1:3000'),
        3000,
      );
    });

    test('parseHostPort returns null for garbage input', () {
      expect(
        DockerBrowserProvider.parseHostPort('no-port-here'),
        isNull,
      );
    });
  });
}
