import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:glue/src/shell/docker_config.dart';

class SessionState {
  final String _dir;
  final List<MountEntry> _dockerMounts = [];
  final List<String> _browserContainerIds = [];

  SessionState._(this._dir);

  List<MountEntry> get dockerMounts => List.unmodifiable(_dockerMounts);
  List<String> get browserContainerIds =>
      List.unmodifiable(_browserContainerIds);

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
        final browserIds =
            (json['browser'] as Map<String, dynamic>?)?['container_ids']
                as List?;
        if (browserIds != null) {
          for (final id in browserIds) {
            state._browserContainerIds.add(id as String);
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

  void addBrowserContainerId(String containerId) {
    if (!_browserContainerIds.contains(containerId)) {
      _browserContainerIds.add(containerId);
      _persist();
    }
  }

  void removeBrowserContainerId(String containerId) {
    _browserContainerIds.remove(containerId);
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
      'browser': {
        'container_ids': _browserContainerIds,
      },
    }));
  }
}
