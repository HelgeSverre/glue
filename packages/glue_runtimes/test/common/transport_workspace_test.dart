import 'dart:convert';

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:glue_runtimes/src/common/fs_transport.dart';
import 'package:test/test.dart';

/// In-memory transport for testing the shared TransportWorkspace.
/// Holds files as bytes; directories are signalled by adding the
/// path to [dirs].
class _FakeFs implements RuntimeFsTransport {
  final Map<String, List<int>> files = {};
  final Set<String> dirs = {};

  @override
  Future<List<int>> readBytes(String path) async =>
      files[path] ?? (throw StateError('not in fake: $path'));

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    files[path] = bytes;
  }

  @override
  Future<bool> exists(String path) async =>
      files.containsKey(path) || dirs.contains(path);

  @override
  Future<bool> isDirectory(String path) async => dirs.contains(path);

  @override
  Future<List<FsTransportEntry>> list(String path) async {
    final base = path.endsWith('/') ? path : '$path/';
    return [
      for (final entry in [...files.keys, ...dirs])
        if (entry.startsWith(base) &&
            !entry.substring(base.length).contains('/'))
          FsTransportEntry(
            name: entry.substring(base.length),
            isDirectory: dirs.contains(entry),
            size: files[entry]?.length ?? 0,
          ),
    ];
  }

  @override
  Future<FsTransportStat?> stat(String path) async {
    if (dirs.contains(path)) {
      return const FsTransportStat(size: 0, isDirectory: true);
    }
    final f = files[path];
    if (f == null) return null;
    return FsTransportStat(size: f.length, isDirectory: false);
  }
}

void main() {
  final mapping = WorkspaceMapping(
    hostCwd: '/Users/h/code/glue',
    runtimeCwd: '/workspace',
  );

  group('TransportWorkspace', () {
    test('readFileAsString round-trips utf8 through the transport', () async {
      final fs = _FakeFs()..files['/workspace/a.txt'] = utf8.encode('hello');
      final ws = TransportWorkspace(fs: fs, mapping: mapping);
      expect(await ws.readFileAsString('/workspace/a.txt'), 'hello');
    });

    test('read of missing path throws WorkspaceAccessError', () async {
      final ws = TransportWorkspace(fs: _FakeFs(), mapping: mapping);
      await expectLater(
        ws.readFileAsString('/workspace/missing'),
        throwsA(isA<WorkspaceAccessError>()),
      );
    });

    test('writeFileAsString stores via the transport', () async {
      final fs = _FakeFs();
      final ws = TransportWorkspace(fs: fs, mapping: mapping);
      await ws.writeFileAsString('/workspace/x.txt', 'héllo');
      expect(utf8.decode(fs.files['/workspace/x.txt']!), 'héllo');
    });

    test('list anchors entry paths under the requested dir + flags dirs',
        () async {
      final fs = _FakeFs()
        ..dirs.add('/workspace')
        ..dirs.add('/workspace/lib')
        ..files['/workspace/README.md'] = utf8.encode('x');
      final ws = TransportWorkspace(fs: fs, mapping: mapping);
      final entries = await ws.list('/workspace');
      expect(
        entries.map((e) => (e.path, e.isDirectory)).toSet(),
        {('/workspace/lib', true), ('/workspace/README.md', false)},
      );
    });

    test('list on non-directory throws WorkspaceAccessError', () async {
      final fs = _FakeFs()..files['/workspace/file'] = utf8.encode('x');
      final ws = TransportWorkspace(fs: fs, mapping: mapping);
      await expectLater(
        ws.list('/workspace/file'),
        throwsA(isA<WorkspaceAccessError>()),
      );
    });

    test('sizeOf returns bytes; throws when missing', () async {
      final fs = _FakeFs()..files['/workspace/a.txt'] = [0, 1, 2, 3, 4];
      final ws = TransportWorkspace(fs: fs, mapping: mapping);
      expect(await ws.sizeOf('/workspace/a.txt'), 5);
      await expectLater(
        ws.sizeOf('/workspace/missing'),
        throwsA(isA<WorkspaceAccessError>()),
      );
    });

    test('exists / isDirectory pass through transport answers', () async {
      final fs = _FakeFs()
        ..files['/workspace/file'] = [1]
        ..dirs.add('/workspace/dir');
      final ws = TransportWorkspace(fs: fs, mapping: mapping);
      expect(await ws.exists('/workspace/file'), isTrue);
      expect(await ws.exists('/workspace/missing'), isFalse);
      expect(await ws.isDirectory('/workspace/dir'), isTrue);
      expect(await ws.isDirectory('/workspace/file'), isFalse);
    });
  });
}
