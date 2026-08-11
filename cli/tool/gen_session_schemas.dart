import 'dart:io';

import 'package:path/path.dart' as p;

void main(List<String> args) {
  final check = args.contains('--check');
  final root = Directory.current.parent.path;
  String read(String name) =>
      File(p.join(root, 'schemas', 'session', name)).readAsStringSync();
  final output =
      '''// GENERATED CODE - DO NOT MODIFY BY HAND.
// Run: dart run tool/gen_session_schemas.dart

const sessionMetaV5SchemaJson = r\'\'\'${read('meta-v5.schema.json')}\'\'\';
const conversationEventV1SchemaJson = r\'\'\'${read('conversation-event-v1.schema.json')}\'\'\';
''';
  final target = File(
    p.join(
      Directory.current.path,
      'lib',
      'src',
      'generated',
      'session_schemas_generated.dart',
    ),
  );
  final publicDir = Directory(
    p.join(root, 'website', 'public', 'schemas', 'session'),
  );
  if (check) {
    var stale = !target.existsSync() || target.readAsStringSync() != output;
    for (final name in [
      'meta-v5.schema.json',
      'conversation-event-v1.schema.json',
    ]) {
      final published = File(p.join(publicDir.path, name));
      stale =
          stale ||
          !published.existsSync() ||
          published.readAsStringSync() != read(name);
    }
    if (stale) {
      stderr.writeln('session schema generated files are stale');
      exitCode = 1;
    }
    return;
  }
  target.parent.createSync(recursive: true);
  target.writeAsStringSync(output);
  Process.runSync(Platform.resolvedExecutable, ['format', target.path]);

  publicDir.createSync(recursive: true);
  for (final name in [
    'meta-v5.schema.json',
    'conversation-event-v1.schema.json',
  ]) {
    File(p.join(publicDir.path, name)).writeAsStringSync(read(name));
  }
}
