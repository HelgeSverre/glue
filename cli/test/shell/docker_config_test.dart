import 'package:test/test.dart';
import 'package:glue/src/shell/docker_config.dart';

void main() {
  group('MountEntry.parse', () {
    test('parses host path only', () {
      final m = MountEntry.parse('/some/path');
      expect(m.hostPath, '/some/path');
      expect(m.containerPath, isNull);
      expect(m.mode, MountMode.rw);
    });

    test('parses host:ro', () {
      final m = MountEntry.parse('/some/path:ro');
      expect(m.hostPath, '/some/path');
      expect(m.containerPath, isNull);
      expect(m.mode, MountMode.ro);
    });

    test('parses host:rw', () {
      final m = MountEntry.parse('/some/path:rw');
      expect(m.hostPath, '/some/path');
      expect(m.containerPath, isNull);
      expect(m.mode, MountMode.rw);
    });

    test('parses host:container', () {
      final m = MountEntry.parse('/host/dir:/container/dir');
      expect(m.hostPath, '/host/dir');
      expect(m.containerPath, '/container/dir');
      expect(m.mode, MountMode.rw);
    });

    test('parses host:container:ro', () {
      final m = MountEntry.parse('/host/dir:/container/dir:ro');
      expect(m.hostPath, '/host/dir');
      expect(m.containerPath, '/container/dir');
      expect(m.mode, MountMode.ro);
    });

    test('parses host:container:rw', () {
      final m = MountEntry.parse('/host/dir:/container/dir:rw');
      expect(m.hostPath, '/host/dir');
      expect(m.containerPath, '/container/dir');
      expect(m.mode, MountMode.rw);
    });

    test('rejects relative paths', () {
      expect(() => MountEntry.parse('relative/path'), throwsArgumentError);
    });

    test('rejects empty spec', () {
      expect(() => MountEntry.parse(''), throwsArgumentError);
      expect(() => MountEntry.parse('  '), throwsArgumentError);
    });

    test('trims whitespace', () {
      final m = MountEntry.parse('  /some/path:ro  ');
      expect(m.hostPath, '/some/path');
      expect(m.mode, MountMode.ro);
    });

    test('toDockerArg produces -v flag value', () {
      final m = MountEntry(hostPath: '/host/dir', mode: MountMode.ro);
      expect(m.toDockerArg(), '/host/dir:/host/dir:ro');
    });

    test('toDockerArg with containerPath', () {
      final m = MountEntry(
        hostPath: '/host/project',
        mode: MountMode.rw,
        containerPath: '/work',
      );
      expect(m.toDockerArg(), '/host/project:/work:rw');
    });
  });

  group('DockerConfig', () {
    test('defaults', () {
      final c = DockerConfig();
      expect(c.enabled, false);
      expect(c.image, 'ubuntu:24.04');
      expect(c.shell, 'sh');
      expect(c.fallbackToHost, true);
      expect(c.mounts, isEmpty);
    });
  });

  group('MountEntry.dedup', () {
    test('later entries override earlier for same host+target+mode', () {
      final a = MountEntry(hostPath: '/foo', mode: MountMode.ro);
      final b = MountEntry(hostPath: '/foo', mode: MountMode.ro);
      final result = MountEntry.dedup([a, b]);
      expect(result, hasLength(1));
    });

    test('keeps entries with different modes', () {
      final a = MountEntry(hostPath: '/foo', mode: MountMode.ro);
      final b = MountEntry(hostPath: '/foo', mode: MountMode.rw);
      final result = MountEntry.dedup([a, b]);
      expect(result, hasLength(2));
    });

    test('keeps same host mounted to different container paths', () {
      final a = MountEntry(
        hostPath: '/data',
        containerPath: '/mnt/a',
      );
      final b = MountEntry(
        hostPath: '/data',
        containerPath: '/mnt/b',
      );
      final result = MountEntry.dedup([a, b]);
      expect(result, hasLength(2));
    });
  });

  group('MountEntry JSON', () {
    test('round-trips through toJson/fromJson', () {
      final original = MountEntry(
        hostPath: '/test/path',
        mode: MountMode.ro,
        addedAt: DateTime.utc(2026, 2, 27),
      );
      final json = original.toJson();
      final restored = MountEntry.fromJson(json);
      expect(restored.hostPath, '/test/path');
      expect(restored.mode, MountMode.ro);
      expect(restored.addedAt, DateTime.utc(2026, 2, 27));
    });

    test('round-trips containerPath', () {
      final original = MountEntry(
        hostPath: '/host',
        containerPath: '/container',
        mode: MountMode.rw,
      );
      final json = original.toJson();
      final restored = MountEntry.fromJson(json);
      expect(restored.containerPath, '/container');
    });
  });
}
