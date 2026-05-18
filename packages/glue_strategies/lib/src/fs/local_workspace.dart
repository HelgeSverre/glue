import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/src/fs/workspace.dart';

/// A [Workspace] backed by the host filesystem via `dart:io`.
///
/// Used for both the host and Docker runtimes — Docker bind-mounts the
/// host cwd at [WorkspaceMapping.runtimeCwd] so the host filesystem is
/// authoritative either way. For Docker, a path expressed in the
/// runtime's vocabulary (e.g. `/workspace/foo.dart`) is translated
/// back to the host path before touching `dart:io`. Paths that are not
/// under the mapping pass through unchanged, preserving compatibility
/// with tools and agents that hand us absolute host paths.
class LocalWorkspace implements Workspace {
  @override
  final WorkspaceMapping mapping;

  LocalWorkspace(this.mapping);

  String _resolve(String path) {
    if (mapping.isIdentity) return path;
    return mapping.toHostPath(path);
  }

  @override
  Future<String> readFileAsString(String path) async {
    final file = File(_resolve(path));
    if (!await file.exists()) {
      throw WorkspaceAccessError('file not found', path);
    }
    return file.readAsString();
  }

  @override
  Future<List<int>> readFileAsBytes(String path) async {
    final file = File(_resolve(path));
    if (!await file.exists()) {
      throw WorkspaceAccessError('file not found', path);
    }
    return file.readAsBytes();
  }

  @override
  Future<void> writeFileAsString(String path, String content) async {
    final file = File(_resolve(path));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  @override
  Future<void> writeFileAsBytes(String path, List<int> bytes) async {
    final file = File(_resolve(path));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<bool> exists(String path) =>
      FileSystemEntity.type(_resolve(path), followLinks: true)
          .then((t) => t != FileSystemEntityType.notFound);

  @override
  Future<bool> isDirectory(String path) async {
    final t = await FileSystemEntity.type(_resolve(path), followLinks: true);
    return t == FileSystemEntityType.directory;
  }

  @override
  Future<List<WorkspaceEntry>> list(String path) async {
    final dir = Directory(_resolve(path));
    if (!await dir.exists()) {
      throw WorkspaceAccessError('directory not found', path);
    }
    final entries = <WorkspaceEntry>[];
    await for (final entry in dir.list()) {
      // Return paths in the same vocabulary the caller used, so an
      // agent that asked about /workspace gets /workspace/... back
      // rather than the underlying host path.
      final hostPath = entry.path;
      final runtimePath = mapping.isIdentity
          ? hostPath
          : (mapping.toRuntimePath(hostPath) ?? hostPath);
      entries.add(WorkspaceEntry(
        path: runtimePath,
        isDirectory: entry is Directory,
      ));
    }
    return entries;
  }

  @override
  Future<int> sizeOf(String path) async {
    final file = File(_resolve(path));
    if (!await file.exists()) {
      throw WorkspaceAccessError('file not found', path);
    }
    final stat = await file.stat();
    return stat.size;
  }
}
