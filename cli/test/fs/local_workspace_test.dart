import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

void main() {
  group('LocalWorkspace (identity mapping)', () {
    late Directory tmp;
    late LocalWorkspace ws;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('glue_local_ws_');
      ws = LocalWorkspace(WorkspaceMapping.host(tmp.path));
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    test('write then read string', () async {
      final path = '${tmp.path}/a.txt';
      await ws.writeFileAsString(path, 'hello world');
      expect(await ws.readFileAsString(path), 'hello world');
    });

    test('write creates parent directories', () async {
      final path = '${tmp.path}/sub/dir/b.txt';
      await ws.writeFileAsString(path, 'nested');
      expect(File(path).existsSync(), isTrue);
    });

    test('write then read bytes', () async {
      final path = '${tmp.path}/bin.bin';
      await ws.writeFileAsBytes(path, [0, 1, 2, 3, 255]);
      expect(await ws.readFileAsBytes(path), [0, 1, 2, 3, 255]);
    });

    test('exists returns true for files and directories', () async {
      final path = '${tmp.path}/c.txt';
      await ws.writeFileAsString(path, 'x');
      expect(await ws.exists(path), isTrue);
      expect(await ws.exists(tmp.path), isTrue);
    });

    test('exists returns false for missing entries', () async {
      expect(await ws.exists('${tmp.path}/nope.txt'), isFalse);
    });

    test('isDirectory distinguishes files from directories', () async {
      final path = '${tmp.path}/d.txt';
      await ws.writeFileAsString(path, 'x');
      expect(await ws.isDirectory(tmp.path), isTrue);
      expect(await ws.isDirectory(path), isFalse);
      expect(await ws.isDirectory('${tmp.path}/missing'), isFalse);
    });

    test('list yields immediate children with isDirectory flag', () async {
      Directory('${tmp.path}/sub').createSync();
      File('${tmp.path}/a.txt').writeAsStringSync('x');
      final entries = await ws.list(tmp.path);
      expect(entries, hasLength(2));
      final sub = entries.singleWhere((e) => e.path.endsWith('sub'));
      final file = entries.singleWhere((e) => e.path.endsWith('a.txt'));
      expect(sub.isDirectory, isTrue);
      expect(file.isDirectory, isFalse);
    });

    test('sizeOf returns the byte length', () async {
      final path = '${tmp.path}/sized.txt';
      await ws.writeFileAsString(path, '12345');
      expect(await ws.sizeOf(path), 5);
    });

    test('read on missing file throws WorkspaceAccessError', () async {
      await expectLater(
        ws.readFileAsString('${tmp.path}/missing.txt'),
        throwsA(isA<WorkspaceAccessError>()),
      );
    });

    test('list on missing directory throws WorkspaceAccessError', () async {
      await expectLater(
        ws.list('${tmp.path}/missing'),
        throwsA(isA<WorkspaceAccessError>()),
      );
    });
  });

  group('LocalWorkspace (translating mapping, simulating Docker)', () {
    late Directory tmp;
    late LocalWorkspace ws;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('glue_local_ws_xlat_');
      ws = LocalWorkspace(
        WorkspaceMapping(hostCwd: tmp.path, runtimeCwd: '/workspace'),
      );
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    test('translates /workspace/foo to <tmp>/foo on read', () async {
      File('${tmp.path}/foo.txt').writeAsStringSync('inside-foo');
      expect(await ws.readFileAsString('/workspace/foo.txt'), 'inside-foo');
    });

    test('translates /workspace on write', () async {
      await ws.writeFileAsString('/workspace/bar.txt', 'inside-bar');
      expect(File('${tmp.path}/bar.txt').readAsStringSync(), 'inside-bar');
    });

    test('list returns paths in runtime vocabulary', () async {
      File('${tmp.path}/x.txt').writeAsStringSync('x');
      Directory('${tmp.path}/y').createSync();
      final entries = await ws.list('/workspace');
      final paths = entries.map((e) => e.path).toList()..sort();
      expect(paths, ['/workspace/x.txt', '/workspace/y']);
    });
  });
}
