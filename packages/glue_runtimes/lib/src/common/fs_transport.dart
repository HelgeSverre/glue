import 'dart:convert';

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';

/// Filesystem entry returned by [RuntimeFsTransport.list].
class FsTransportEntry {
  final String name;
  final bool isDirectory;
  final int size;

  const FsTransportEntry({
    required this.name,
    required this.isDirectory,
    this.size = 0,
  });
}

/// File metadata returned by [RuntimeFsTransport.stat].
class FsTransportStat {
  final int size;
  final bool isDirectory;

  const FsTransportStat({required this.size, required this.isDirectory});
}

/// Narrow filesystem contract that each cloud runtime adapter
/// implements on top of its underlying transport (REST client,
/// `sprite` CLI, Modal sidecar). [TransportWorkspace] consumes this
/// and exposes the standard [Workspace] interface — so the three
/// adapters share one workspace implementation instead of each
/// re-implementing read/write/list/exists/stat.
abstract class RuntimeFsTransport {
  Future<List<int>> readBytes(String path);
  Future<void> writeBytes(String path, List<int> bytes);
  Future<bool> exists(String path);
  Future<bool> isDirectory(String path);
  Future<List<FsTransportEntry>> list(String path);

  /// Returns metadata for [path], or `null` when missing.
  Future<FsTransportStat?> stat(String path);
}

/// A [Workspace] backed by a [RuntimeFsTransport].
///
/// Each adapter (`daytona`, `sprites`, `modal`) wraps its
/// client/cli/sidecar in a `*FsTransport` impl (10-30 lines) and
/// instantiates this — the workspace logic (path translation,
/// `WorkspaceAccessError` mapping, list-entry path anchoring) is
/// implemented here once.
class TransportWorkspace implements Workspace {
  final RuntimeFsTransport fs;

  @override
  final WorkspaceMapping mapping;

  TransportWorkspace({required this.fs, required this.mapping});

  @override
  Future<String> readFileAsString(String path) async {
    if (!await fs.exists(path)) {
      throw WorkspaceAccessError('file not found', path);
    }
    return utf8.decode(await fs.readBytes(path), allowMalformed: true);
  }

  @override
  Future<List<int>> readFileAsBytes(String path) async {
    if (!await fs.exists(path)) {
      throw WorkspaceAccessError('file not found', path);
    }
    return fs.readBytes(path);
  }

  @override
  Future<void> writeFileAsString(String path, String content) =>
      fs.writeBytes(path, utf8.encode(content));

  @override
  Future<void> writeFileAsBytes(String path, List<int> bytes) =>
      fs.writeBytes(path, bytes);

  @override
  Future<bool> exists(String path) => fs.exists(path);

  @override
  Future<bool> isDirectory(String path) => fs.isDirectory(path);

  @override
  Future<List<WorkspaceEntry>> list(String path) async {
    if (!await fs.isDirectory(path)) {
      throw WorkspaceAccessError('directory not found', path);
    }
    final entries = await fs.list(path);
    final base = path.endsWith('/') ? path : '$path/';
    return entries
        .map(
          (e) => WorkspaceEntry(
            path: '$base${e.name}',
            isDirectory: e.isDirectory,
          ),
        )
        .toList();
  }

  @override
  Future<int> sizeOf(String path) async {
    final stat = await fs.stat(path);
    if (stat == null) {
      throw WorkspaceAccessError('file not found', path);
    }
    return stat.size;
  }
}
