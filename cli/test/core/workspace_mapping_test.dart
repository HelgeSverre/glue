import 'package:glue_core/glue_core.dart';
import 'package:test/test.dart';

void main() {
  group('WorkspaceMapping', () {
    test('host factory produces an identity mapping', () {
      final m = WorkspaceMapping.host('/Users/h/code/glue');
      expect(m.isIdentity, isTrue);
      expect(m.toRuntimePath('/Users/h/code/glue/lib/foo.dart'),
          '/Users/h/code/glue/lib/foo.dart');
      expect(m.toHostPath('/Users/h/code/glue/lib/foo.dart'),
          '/Users/h/code/glue/lib/foo.dart');
    });

    test('docker-style mapping translates host → /workspace', () {
      final m = WorkspaceMapping(
        hostCwd: '/Users/h/code/glue',
        runtimeCwd: '/workspace',
      );
      expect(m.isIdentity, isFalse);
      expect(m.toRuntimePath('/Users/h/code/glue'), '/workspace');
      expect(m.toRuntimePath('/Users/h/code/glue/lib/foo.dart'),
          '/workspace/lib/foo.dart');
    });

    test('docker-style mapping translates /workspace → host', () {
      final m = WorkspaceMapping(
        hostCwd: '/Users/h/code/glue',
        runtimeCwd: '/workspace',
      );
      expect(m.toHostPath('/workspace'), '/Users/h/code/glue');
      expect(m.toHostPath('/workspace/lib/foo.dart'),
          '/Users/h/code/glue/lib/foo.dart');
    });

    test('toRuntimePath returns null for paths outside hostCwd', () {
      final m = WorkspaceMapping(
        hostCwd: '/Users/h/code/glue',
        runtimeCwd: '/workspace',
      );
      expect(m.toRuntimePath('/etc/passwd'), isNull);
      expect(m.toRuntimePath('/Users/h/other/repo/x'), isNull);
    });

    test('toHostPath passes through paths outside runtimeCwd', () {
      final m = WorkspaceMapping(
        hostCwd: '/Users/h/code/glue',
        runtimeCwd: '/workspace',
      );
      expect(m.toHostPath('/etc/passwd'), '/etc/passwd');
    });

    test('artifactsDir defaults under runtimeCwd', () {
      final m = WorkspaceMapping(
        hostCwd: '/h/cwd',
        runtimeCwd: '/workspace',
      );
      expect(m.artifactsDir, '/workspace/.glue/artifacts');
    });

    test('artifactsDir can be overridden', () {
      final m = WorkspaceMapping(
        hostCwd: '/h/cwd',
        runtimeCwd: '/workspace',
        artifactsDir: '/tmp/glue',
      );
      expect(m.artifactsDir, '/tmp/glue');
    });

    test('does not mismatch a path that shares a prefix but no slash', () {
      // /workspace-other should NOT be translated as if it were under
      // /workspace.
      final m = WorkspaceMapping(
        hostCwd: '/Users/h/code/glue',
        runtimeCwd: '/workspace',
      );
      expect(m.toHostPath('/workspace-other/foo'), '/workspace-other/foo');
    });
  });
}
