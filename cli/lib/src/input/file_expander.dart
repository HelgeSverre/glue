import 'dart:io';
import 'package:glue/src/config/constants.dart';

import 'package:path/path.dart' as p;

final _refPattern = RegExp(
  r'''(?:^|(?<=\s))@(?:"([^"]+)"|'([^']+)'|([\w./\-]+))''',
);

const _langTags = <String, String>{
  '.dart': 'dart',
  '.json': 'json',
  '.yaml': 'yaml',
  '.yml': 'yaml',
  '.md': 'markdown',
  '.sh': 'sh',
  '.ts': 'typescript',
  '.js': 'javascript',
  '.py': 'python',
  '.html': 'html',
  '.css': 'css',
  '.sql': 'sql',
  '.rs': 'rust',
  '.go': 'go',
};

List<String> extractFileRefs(String input) {
  return _refPattern.allMatches(input).map((m) {
    return m.group(1) ?? m.group(2) ?? m.group(3)!;
  }).toList();
}

String expandFileRefs(String input, {String? cwd}) {
  return input.replaceAllMapped(_refPattern, (m) {
    final fullMatch = m.group(0)!;
    final filePath = m.group(1) ?? m.group(2) ?? m.group(3)!;
    final resolved = cwd != null ? p.join(cwd, filePath) : filePath;
    final file = File(resolved);

    if (!file.existsSync()) {
      return '$fullMatch [not found]';
    }

    final stat = file.statSync();
    if (stat.size > AppConstants.maxFileExpansionBytes) {
      final kb = (stat.size / 1024).round();
      return '$fullMatch [too large: $kb KB]';
    }

    final contents = file.readAsStringSync();
    final ext = p.extension(filePath);
    final lang = _langTags[ext] ?? '';
    final fence = _computeFence(contents);

    return '\n\n[$filePath]\n$fence$lang\n$contents\n$fence';
  });
}

String _computeFence(String contents) {
  var maxRun = 0;
  var current = 0;
  for (final ch in contents.codeUnits) {
    if (ch == 0x60) {
      current++;
      if (current > maxRun) maxRun = current;
    } else {
      current = 0;
    }
  }
  final needed = maxRun >= 3 ? maxRun + 1 : 3;
  return '`' * needed;
}
