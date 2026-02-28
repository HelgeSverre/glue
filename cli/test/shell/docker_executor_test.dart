import 'dart:io';
import 'package:test/test.dart';
import 'package:glue/src/shell/docker_executor.dart';
import 'package:glue/src/shell/docker_config.dart';

void main() {
  group('DockerExecutor', () {
    test('buildDockerArgs constructs correct argument list', () {
      final executor = DockerExecutor(
        config: DockerConfig(image: 'alpine:latest', shell: 'sh'),
        cwd: '/home/user/project',
        mounts: [
          MountEntry(hostPath: '/home/user/libs', mode: MountMode.rw),
          MountEntry(hostPath: '/home/user/data', mode: MountMode.ro),
        ],
      );

      final args = executor.buildDockerArgs('echo hello', '/tmp/cid');
      expect(args, containsAllInOrder(['run', '--rm', '-i']));
      expect(args, contains('--cidfile'));
      expect(args, contains('/tmp/cid'));
      expect(args, contains('-w'));
      expect(args, contains('/work'));
      expect(args, contains('alpine:latest'));
      expect(args.last, 'echo hello');

      // Check mount args
      final vArgs = <String>[];
      for (var i = 0; i < args.length; i++) {
        if (args[i] == '-v' && i + 1 < args.length) {
          vArgs.add(args[i + 1]);
        }
      }
      expect(vArgs, contains('/home/user/project:/work:rw'));
      expect(vArgs, contains('/home/user/libs:/home/user/libs:rw'));
      expect(vArgs, contains('/home/user/data:/home/user/data:ro'));
    });

    test('buildDockerArgs with no extra mounts', () {
      final executor = DockerExecutor(
        config: DockerConfig(image: 'ubuntu:24.04', shell: 'bash'),
        cwd: '/my/project',
        mounts: [],
      );

      final args = executor.buildDockerArgs('ls', '/tmp/cid');
      expect(args, contains('ubuntu:24.04'));
      expect(args, containsAllInOrder(['bash', '-c', 'ls']));

      final vArgs = <String>[];
      for (var i = 0; i < args.length; i++) {
        if (args[i] == '-v' && i + 1 < args.length) {
          vArgs.add(args[i + 1]);
        }
      }
      expect(vArgs, hasLength(1));
      expect(vArgs.first, '/my/project:/work:rw');
    });

    test('buildDockerArgs deduplicates identical mounts', () {
      final executor = DockerExecutor(
        config: DockerConfig(image: 'alpine:latest', shell: 'sh'),
        cwd: '/project',
        mounts: [
          MountEntry(hostPath: '/shared', mode: MountMode.rw),
          MountEntry(hostPath: '/shared', mode: MountMode.rw),
        ],
      );

      final args = executor.buildDockerArgs('echo hi', '/tmp/cid');
      final vArgs = <String>[];
      for (var i = 0; i < args.length; i++) {
        if (args[i] == '-v' && i + 1 < args.length) {
          vArgs.add(args[i + 1]);
        }
      }
      // cwd + 1 deduped mount
      expect(vArgs, hasLength(2));
      expect(vArgs, contains('/shared:/shared:rw'));
    });

    // Integration test — only runs if Docker is available
    test('runCapture executes in container', () async {
      final result = await Process.run('docker', ['--version']);
      if (result.exitCode != 0) {
        markTestSkipped('Docker not available');
        return;
      }

      final executor = DockerExecutor(
        config: DockerConfig(image: 'alpine:latest', shell: 'sh'),
        cwd: Directory.current.path,
        mounts: [],
      );

      final r = await executor.runCapture('echo hello');
      expect(r.stdout.trim(), 'hello');
      expect(r.exitCode, 0);
    }, timeout: Timeout(Duration(seconds: 30)));
  });
}
