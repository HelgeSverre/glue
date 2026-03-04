import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:glue/src/storage/session_state.dart';
import 'package:glue/src/shell/docker_config.dart';

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('session_state_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  group('SessionState', () {
    test('load returns empty state when file missing', () {
      final state = SessionState.load(tmpDir.path);
      expect(state.dockerMounts, isEmpty);
    });

    test('addMount persists to state.json', () {
      final state = SessionState.load(tmpDir.path);
      state.addMount(MountEntry(hostPath: '/test/dir', mode: MountMode.rw));

      final file = File(p.join(tmpDir.path, 'state.json'));
      expect(file.existsSync(), true);

      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(json['version'], 1);
      final docker = json['docker'] as Map<String, dynamic>;
      expect(docker['mounts'] as List, hasLength(1));
    });

    test('removeMount removes by path', () {
      final state = SessionState.load(tmpDir.path);
      state.addMount(MountEntry(hostPath: '/a'));
      state.addMount(MountEntry(hostPath: '/b'));
      state.removeMount('/a');
      expect(state.dockerMounts.map((m) => m.hostPath), ['/b']);
    });

    test('load restores persisted mounts', () {
      final state1 = SessionState.load(tmpDir.path);
      state1.addMount(MountEntry(hostPath: '/persist'));

      final state2 = SessionState.load(tmpDir.path);
      expect(state2.dockerMounts.map((m) => m.hostPath), ['/persist']);
    });

    test('addMount deduplicates by path', () {
      final state = SessionState.load(tmpDir.path);
      state.addMount(MountEntry(hostPath: '/dup', mode: MountMode.ro));
      state.addMount(MountEntry(hostPath: '/dup', mode: MountMode.rw));
      expect(state.dockerMounts, hasLength(1));
      expect(state.dockerMounts.first.mode, MountMode.rw);
    });

    test('atomic persist does not leave temporary files behind', () {
      final state = SessionState.load(tmpDir.path);
      state.addMount(MountEntry(hostPath: '/persist'));

      expect(File(p.join(tmpDir.path, 'state.json')).existsSync(), isTrue);
      expect(File(p.join(tmpDir.path, 'state.json.tmp')).existsSync(), isFalse);
    });

    test('load ignores unknown future schema versions', () {
      final file = File(p.join(tmpDir.path, 'state.json'));
      file.writeAsStringSync(jsonEncode({
        'version': 99,
        'docker': {
          'mounts': [
            {'host_path': '/future', 'mode': 'rw'}
          ],
        },
      }));

      final state = SessionState.load(tmpDir.path);
      expect(state.dockerMounts, isEmpty);
    });
  });
}
