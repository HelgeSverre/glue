import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class SessionMeta {
  final String id;
  final String cwd;
  final String model;
  final String provider;
  final DateTime startTime;
  DateTime? endTime;

  SessionMeta({
    required this.id,
    required this.cwd,
    required this.model,
    required this.provider,
    required this.startTime,
    this.endTime,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'cwd': cwd,
    'model': model,
    'provider': provider,
    'start_time': startTime.toIso8601String(),
    if (endTime != null) 'end_time': endTime!.toIso8601String(),
  };
}

class SessionStore {
  final String sessionDir;
  final SessionMeta meta;
  late final IOSink _conversationSink;

  SessionStore({required this.sessionDir, required this.meta}) {
    Directory(sessionDir).createSync(recursive: true);
    _conversationSink = File(p.join(sessionDir, 'conversation.jsonl'))
        .openWrite(mode: FileMode.append);
    _writeMeta();
  }

  void _writeMeta() {
    const encoder = JsonEncoder.withIndent('  ');
    File(p.join(sessionDir, 'meta.json'))
        .writeAsStringSync(encoder.convert(meta.toJson()));
  }

  void logEvent(String type, Map<String, dynamic> data) {
    final record = {
      'timestamp': DateTime.now().toIso8601String(),
      'type': type,
      ...data,
    };
    _conversationSink.writeln(jsonEncode(record));
  }

  Future<void> close() async {
    meta.endTime = DateTime.now();
    _writeMeta();
    await _conversationSink.flush();
    await _conversationSink.close();
  }
}
