import 'dart:io';

void atomicWrite(File file, String content) {
  file.parent.createSync(recursive: true);
  final tmp = File('${file.path}.tmp');
  tmp.writeAsStringSync(content);
  if (Platform.isWindows && file.existsSync()) {
    file.deleteSync();
  }
  tmp.renameSync(file.path);
}
