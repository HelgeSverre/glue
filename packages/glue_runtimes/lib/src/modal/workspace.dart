import 'package:glue_runtimes/src/common/fs_transport.dart';
import 'package:glue_runtimes/src/modal/sidecar.dart';

export 'package:glue_runtimes/src/common/fs_transport.dart'
    show TransportWorkspace;

/// Modal's filesystem layer mapped onto the shared
/// [RuntimeFsTransport] contract. All ops delegate to the python
/// sidecar's JSON-RPC bridge (which uses Modal's
/// `Sandbox.filesystem.read_bytes` / `write_bytes` under the hood).
class ModalFsTransport implements RuntimeFsTransport {
  final ModalSidecarBase sidecar;

  ModalFsTransport({required this.sidecar});

  @override
  Future<List<int>> readBytes(String path) => sidecar.readFile(path);

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      sidecar.writeFile(path, bytes);

  @override
  Future<bool> exists(String path) => sidecar.exists(path);

  @override
  Future<bool> isDirectory(String path) => sidecar.isDirectory(path);

  @override
  Future<List<FsTransportEntry>> list(String path) async {
    final entries = await sidecar.listDir(path);
    return entries
        .map((e) => FsTransportEntry(
              name: e.name,
              isDirectory: e.isDirectory,
              size: e.size,
            ))
        .toList();
  }

  @override
  Future<FsTransportStat?> stat(String path) async {
    final s = await sidecar.stat(path);
    if (s == null) return null;
    return FsTransportStat(size: s.size, isDirectory: s.isDirectory);
  }
}
