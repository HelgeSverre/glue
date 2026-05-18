import 'package:glue_runtimes/src/common/fs_transport.dart';
import 'package:glue_runtimes/src/sprites/cli.dart';

export 'package:glue_runtimes/src/common/fs_transport.dart'
    show TransportWorkspace;

/// Sprites' filesystem layer mapped onto the shared
/// [RuntimeFsTransport] contract. Sprites has no stable REST `/files`
/// endpoint at this API version, so reads / writes / lists all
/// layer on top of `sprite exec` via the [SpritesFs] extension
/// helpers.
class SpritesFsTransport implements RuntimeFsTransport {
  final SpritesCliBase cli;
  final String spriteName;

  SpritesFsTransport({required this.cli, required this.spriteName});

  @override
  Future<List<int>> readBytes(String path) =>
      cli.readFileBytes(spriteName, path);

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      cli.writeFileBytes(spriteName, path, bytes);

  @override
  Future<bool> exists(String path) => cli.pathExists(spriteName, path);

  @override
  Future<bool> isDirectory(String path) => cli.isDirectory(spriteName, path);

  @override
  Future<List<FsTransportEntry>> list(String path) async {
    final entries = await cli.listDir(spriteName, path);
    return entries
        .map((e) => FsTransportEntry(name: e.name, isDirectory: e.isDirectory))
        .toList();
  }

  @override
  Future<FsTransportStat?> stat(String path) async {
    final size = await cli.sizeOf(spriteName, path);
    if (size == null) return null;
    return FsTransportStat(
      size: size,
      isDirectory: await cli.isDirectory(spriteName, path),
    );
  }
}
