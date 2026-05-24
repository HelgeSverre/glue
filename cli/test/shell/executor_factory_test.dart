import 'dart:io';

import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

void main() {
  group('ExecutorFactory', () {
    test('returns HostExecutor when docker disabled', () async {
      final executor = await ExecutorFactory.create(
        shellConfig: const ShellConfig(),
        dockerConfig: const DockerConfig(enabled: false),
        cwd: Directory.current.path,
      );
      expect(executor, isA<HostExecutor>());
    });

    test(
      'returns HostExecutor with fallback when docker unavailable',
      () async {
        final executor = await ExecutorFactory.create(
          shellConfig: const ShellConfig(),
          dockerConfig: const DockerConfig(enabled: true, fallbackToHost: true),
          cwd: Directory.current.path,
          dockerAvailable: false,
        );
        expect(executor, isA<HostExecutor>());
      },
    );

    test('throws when docker required but unavailable', () async {
      expect(
        () => ExecutorFactory.create(
          shellConfig: const ShellConfig(),
          dockerConfig: const DockerConfig(
            enabled: true,
            fallbackToHost: false,
          ),
          cwd: Directory.current.path,
          dockerAvailable: false,
        ),
        throwsStateError,
      );
    });

    test('returns DockerExecutor when docker enabled and available', () async {
      final executor = await ExecutorFactory.create(
        shellConfig: const ShellConfig(),
        dockerConfig: const DockerConfig(enabled: true, image: 'alpine:latest'),
        cwd: '/test/cwd',
        dockerAvailable: true,
      );
      expect(executor, isA<DockerExecutor>());
    });

    test('merges config and session mounts', () async {
      final executor = await ExecutorFactory.create(
        shellConfig: const ShellConfig(),
        dockerConfig: const DockerConfig(
          enabled: true,
          mounts: [MountEntry(hostPath: '/config/mount')],
        ),
        cwd: '/test/cwd',
        sessionMounts: const [MountEntry(hostPath: '/session/mount')],
        dockerAvailable: true,
      );
      final docker = executor as DockerExecutor;
      expect(
        docker.mounts.map((m) => m.hostPath),
        containsAll(['/config/mount', '/session/mount']),
      );
    });
  });
}
