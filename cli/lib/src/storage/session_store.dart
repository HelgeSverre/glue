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
  late final File _conversationFile;

  SessionStore({required this.sessionDir, required this.meta}) {
    Directory(sessionDir).createSync(recursive: true);
    _conversationFile = File(p.join(sessionDir, 'conversation.jsonl'));
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
    _conversationFile.writeAsStringSync(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
    );
  }

  Future<void> close() async {
    meta.endTime = DateTime.now();
    _writeMeta();
  }

  static List<SessionMeta> listSessions(String sessionsDir) {
    final dir = Directory(sessionsDir);
    if (!dir.existsSync()) return [];

    final sessions = <SessionMeta>[];
    for (final entry in dir.listSync()) {
      if (entry is! Directory) continue;
      final metaFile = File(p.join(entry.path, 'meta.json'));
      if (!metaFile.existsSync()) continue;
      try {
        final json =
            jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
        sessions.add(SessionMeta(
          id: json['id'] as String,
          cwd: json['cwd'] as String? ?? '',
          model: json['model'] as String? ?? 'unknown',
          provider: json['provider'] as String? ?? 'unknown',
          startTime: DateTime.parse(json['start_time'] as String),
          endTime: json['end_time'] != null
              ? DateTime.parse(json['end_time'] as String)
              : null,
        ));
      } catch (_) {}
    }

    sessions.sort((a, b) => b.startTime.compareTo(a.startTime));
    return sessions;
  }

  static List<Map<String, dynamic>> loadConversation(String sessionDir) {
    final file = File(p.join(sessionDir, 'conversation.jsonl'));
    if (!file.existsSync()) return [];

    final events = <Map<String, dynamic>>[];
    for (final line in file.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      try {
        events.add(jsonDecode(line) as Map<String, dynamic>);
      } catch (_) {}
    }
    return events;
  }
}
