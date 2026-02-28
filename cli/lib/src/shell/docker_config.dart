import 'package:path/path.dart' as p;

enum MountMode { ro, rw }

class MountEntry {
  final String hostPath;
  final MountMode mode;
  final String? containerPath;
  final DateTime? addedAt;

  MountEntry({
    required this.hostPath,
    this.mode = MountMode.rw,
    this.containerPath,
    this.addedAt,
  });

  factory MountEntry.parse(String spec) {
    var s = spec.trim();
    if (s.isEmpty) throw ArgumentError('Mount spec cannot be empty');

    var mode = MountMode.rw;
    String? containerPath;

    // Strip optional :ro / :rw suffix (parse from right).
    final lastColon = s.lastIndexOf(':');
    if (lastColon != -1) {
      final tail = s.substring(lastColon + 1);
      if (tail == 'ro' || tail == 'rw') {
        mode = tail == 'ro' ? MountMode.ro : MountMode.rw;
        s = s.substring(0, lastColon);
      }
    }

    // Strip optional :<containerPath> (only if RHS is a POSIX absolute path).
    final colon2 = s.lastIndexOf(':');
    if (colon2 != -1) {
      final rhs = s.substring(colon2 + 1);
      if (rhs.startsWith('/')) {
        containerPath = rhs;
        s = s.substring(0, colon2);
      }
    }

    final hostPath = s;
    if (!_isAbsoluteHostPath(hostPath)) {
      throw ArgumentError('Mount host path must be absolute: $hostPath');
    }

    return MountEntry(
      hostPath: hostPath,
      containerPath: containerPath,
      mode: mode,
    );
  }

  static bool _isAbsoluteHostPath(String path) {
    if (p.isAbsolute(path)) return true;
    if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path)) return true;
    if (path.startsWith(r'\\')) return true;
    return false;
  }

  String toDockerArg() {
    final target = containerPath ?? hostPath;
    return '$hostPath:$target:${mode.name}';
  }

  static List<MountEntry> dedup(List<MountEntry> entries) {
    final map = <String, MountEntry>{};
    for (final e in entries) {
      final target = e.containerPath ?? e.hostPath;
      final key = '${e.hostPath}->$target:${e.mode.name}';
      map[key] = e;
    }
    return map.values.toList();
  }

  Map<String, dynamic> toJson() => {
        'host_path': hostPath,
        'mode': mode.name,
        if (containerPath != null) 'container_path': containerPath,
        if (addedAt != null) 'added_at': addedAt!.toIso8601String(),
      };

  factory MountEntry.fromJson(Map<String, dynamic> json) => MountEntry(
        hostPath: json['host_path'] as String,
        mode: json['mode'] == 'ro' ? MountMode.ro : MountMode.rw,
        containerPath: json['container_path'] as String?,
        addedAt: json['added_at'] != null
            ? DateTime.parse(json['added_at'] as String)
            : null,
      );
}

class DockerConfig {
  final bool enabled;
  final String image;
  final String shell;
  final bool fallbackToHost;
  final List<MountEntry> mounts;

  const DockerConfig({
    this.enabled = false,
    this.image = 'ubuntu:24.04',
    this.shell = 'sh',
    this.fallbackToHost = true,
    this.mounts = const [],
  });
}
