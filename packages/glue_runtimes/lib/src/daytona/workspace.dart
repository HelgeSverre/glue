import 'package:glue_runtimes/src/common/fs_transport.dart';
import 'package:glue_runtimes/src/daytona/client.dart';

// Re-export the shared TransportWorkspace as DaytonaWorkspace so
// existing callers (and the barrel) keep their type name. The
// behaviour lives in TransportWorkspace; this file only provides the
// daytona-specific [RuntimeFsTransport] glue.
export 'package:glue_runtimes/src/common/fs_transport.dart'
    show TransportWorkspace;

/// Daytona's filesystem layer mapped onto the shared
/// [RuntimeFsTransport] contract. Each method translates 404
/// responses into `null` / `false` so [TransportWorkspace] can
/// surface them as [WorkspaceAccessError].
class DaytonaFsTransport implements RuntimeFsTransport {
  final DaytonaClient client;
  final DaytonaSandbox sandbox;

  DaytonaFsTransport({required this.client, required this.sandbox});

  @override
  Future<List<int>> readBytes(String path) => client.readFile(sandbox, path);

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      client.writeFile(sandbox, path, bytes);

  @override
  Future<bool> exists(String path) async {
    final stat = await client.stat(sandbox, path);
    return stat != null;
  }

  @override
  Future<bool> isDirectory(String path) async {
    final stat = await client.stat(sandbox, path);
    return stat?.isDirectory ?? false;
  }

  @override
  Future<List<FsTransportEntry>> list(String path) async {
    final entries = await client.listDir(sandbox, path);
    return entries
        .map(
          (e) => FsTransportEntry(
            name: e.name,
            isDirectory: e.isDirectory,
            size: e.size,
          ),
        )
        .toList();
  }

  @override
  Future<FsTransportStat?> stat(String path) async {
    final s = await client.stat(sandbox, path);
    if (s == null) return null;
    return FsTransportStat(size: s.size, isDirectory: s.isDirectory);
  }
}
