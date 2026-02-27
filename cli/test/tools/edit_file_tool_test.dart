import 'dart:io';
import 'package:test/test.dart';
import 'package:glue/glue.dart';

void main() {
  late Directory tmpDir;
  late EditFileTool tool;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('edit_file_test_');
    tool = EditFileTool();
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  File writeFile(String name, String content) {
    final f = File('${tmpDir.path}/$name');
    f.writeAsStringSync(content);
    return f;
  }

  test('replaces single-line match', () async {
    final f = writeFile('a.dart', 'int x = 1;\nint y = 2;\n');
    final result = await tool.execute({
      'path': f.path,
      'old_string': 'int x = 1;',
      'new_string': 'int x = 42;',
    });
    expect(result, contains('Applied edit'));
    expect(f.readAsStringSync(), 'int x = 42;\nint y = 2;\n');
  });

  test('replaces multi-line match', () async {
    final f = writeFile('b.dart', 'void foo() {\n  print("hello");\n}\n');
    final result = await tool.execute({
      'path': f.path,
      'old_string': 'void foo() {\n  print("hello");\n}',
      'new_string': 'void foo() {\n  print("world");\n  return;\n}',
    });
    expect(result, contains('Applied edit'));
    expect(f.readAsStringSync(),
        'void foo() {\n  print("world");\n  return;\n}\n');
  });

  test('errors when old_string not found', () async {
    final f = writeFile('c.dart', 'int x = 1;\n');
    final result = await tool.execute({
      'path': f.path,
      'old_string': 'int y = 2;',
      'new_string': 'int y = 3;',
    });
    expect(result, contains('not found'));
  });

  test('errors when old_string is ambiguous', () async {
    final f = writeFile('d.dart', 'foo();\nbar();\nfoo();\n');
    final result = await tool.execute({
      'path': f.path,
      'old_string': 'foo();',
      'new_string': 'baz();',
    });
    expect(result, contains('multiple'));
  });

  test('creates file when old_string is empty', () async {
    final path = '${tmpDir.path}/new_file.dart';
    final result = await tool.execute({
      'path': path,
      'old_string': '',
      'new_string': 'void main() {}\n',
    });
    expect(result, contains('Created'));
    expect(File(path).readAsStringSync(), 'void main() {}\n');
  });

  test('deletes content when new_string is empty', () async {
    final f = writeFile('e.dart', 'line1\nline2\nline3\n');
    final result = await tool.execute({
      'path': f.path,
      'old_string': 'line2\n',
      'new_string': '',
    });
    expect(result, contains('Applied edit'));
    expect(f.readAsStringSync(), 'line1\nline3\n');
  });

  test('errors when file not found and old_string non-empty', () async {
    final result = await tool.execute({
      'path': '${tmpDir.path}/nope.dart',
      'old_string': 'hello',
      'new_string': 'world',
    });
    expect(result, contains('not found'));
  });

  test('errors on missing path', () async {
    final result = await tool.execute({
      'old_string': 'a',
      'new_string': 'b',
    });
    expect(result, contains('Error'));
  });

  test('handles whitespace-only old_string for insert at beginning', () async {
    final f = writeFile('f.dart', 'content\n');
    final result = await tool.execute({
      'path': f.path,
      'old_string': '',
      'new_string': '// header\n',
    });
    expect(result, contains('Created'));
  });
}
