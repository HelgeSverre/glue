import 'package:glue_core/glue_core.dart';

/// A single entry returned by [Workspace.list].
class WorkspaceEntry {
  /// Absolute or relative path of this entry, as understood by the
  /// runtime (e.g. `/workspace/lib/foo.dart`).
  final String path;
  final bool isDirectory;

  WorkspaceEntry({required this.path, required this.isDirectory});
}

/// Thrown when a [Workspace] operation references a path that the
/// implementation refuses to act on — for example, a path outside the
/// declared [WorkspaceMapping.runtimeCwd] for a cloud workspace, or a
/// missing parent directory for a read.
class WorkspaceAccessError implements Exception {
  final String message;
  final String path;
  WorkspaceAccessError(this.message, this.path);

  @override
  String toString() => 'WorkspaceAccessError: $message ($path)';
}

/// Filesystem-level operations over the working tree of a runtime.
///
/// Implementations:
/// - [LocalWorkspace] — `dart:io` passthrough for host and Docker
///   (Docker bind-mounts the host cwd so the host filesystem is
///   authoritative).
/// - Cloud workspaces (`DaytonaWorkspace`, …) — route through the
///   provider's HTTP filesystem API.
///
/// Tools (`ReadFileTool`, `WriteFileTool`, `EditFileTool`,
/// `ListDirectoryTool`) talk to this interface so they work uniformly
/// across runtimes.
abstract class Workspace {
  /// Path translation metadata. For [LocalWorkspace] this is usually
  /// the identity mapping; for cloud workspaces this maps `/workspace`
  /// to the host cwd the user is editing locally.
  WorkspaceMapping get mapping;

  /// Reads the file at [path] as a UTF-8 string.
  ///
  /// Throws [WorkspaceAccessError] when the file does not exist or the
  /// implementation refuses to access [path].
  Future<String> readFileAsString(String path);

  /// Reads the file at [path] as raw bytes.
  Future<List<int>> readFileAsBytes(String path);

  /// Writes [content] to [path], creating parent directories as
  /// needed. Overwrites any existing file at [path].
  Future<void> writeFileAsString(String path, String content);

  /// Writes [bytes] to [path], creating parent directories as needed.
  Future<void> writeFileAsBytes(String path, List<int> bytes);

  /// Returns true when [path] refers to an existing file or directory.
  Future<bool> exists(String path);

  /// Returns whether [path] is a directory. Returns `false` for files
  /// and for paths that do not exist.
  Future<bool> isDirectory(String path);

  /// Returns the immediate children of [path]. The order is
  /// implementation-defined.
  Future<List<WorkspaceEntry>> list(String path);

  /// Returns the size of the file at [path] in bytes. Throws
  /// [WorkspaceAccessError] when the file does not exist.
  Future<int> sizeOf(String path);
}
