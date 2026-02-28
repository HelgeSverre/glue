import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../shell/docker_config.dart';

class SessionState {
  final String _dir;
  final List<MountEntry> _dockerMounts = [];

  SessionState._(this._dir);

  List<MountEntry> get dockerMounts => List.unmodifiable(_dockerMounts);

  factory SessionState.load(String sessionDir) {
    final state = SessionState._(sessionDir);
    final file = File(p.join(sessionDir, 'state.json'));
    if (file.existsSync()) {
      try {
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final docker = json['docker'] as Map<String, dynamic>?;
        final mounts = docker?['mounts'] as List?;
        if (mounts != null) {
          for (final m in mounts) {
            state._dockerMounts
                .add(MountEntry.fromJson(m as Map<String, dynamic>));
          }
        }
      } catch (_) {}
    }
    return state;
  }

  void addMount(MountEntry mount) {
    _dockerMounts.removeWhere((m) => m.hostPath == mount.hostPath);
    _dockerMounts.add(mount);
    _persist();
  }

  void removeMount(String hostPath) {
    _dockerMounts.removeWhere((m) => m.hostPath == hostPath);
    _persist();
  }

  void _persist() {
    final file = File(p.join(_dir, 'state.json'));
    file.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    file.writeAsStringSync(encoder.convert({
      'version': 1,
      'docker': {
        'mounts': _dockerMounts.map((m) => m.toJson()).toList(),
      },
    }));
  }
}
