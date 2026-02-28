import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Metadata for a saved session, including model, provider, and timing.
class SessionMeta {
  static const int currentSchemaVersion = 2;

  final int schemaVersion;
  final String id;
  final String cwd;
  final String? projectPath;
  final String model;
  final String provider;
  final DateTime startTime;
  DateTime? endTime;
  final String? forkedFrom;

  // Git context.
  final String? worktreePath;
  final String? branch;
  final String? baseBranch;
  final String? repoRemote;
  final String? headSha;

  // Display & organization.
  String? title;
  final List<String> tags;

  // PR lifecycle.
  String? prUrl;
  String? prStatus;

  // Metrics.
  int? tokenCount;
  double? cost;

  // Summary.
  String? summary;

  SessionMeta({
    this.schemaVersion = currentSchemaVersion,
    required this.id,
    required this.cwd,
    this.projectPath,
    required this.model,
    required this.provider,
    required this.startTime,
    this.endTime,
    this.forkedFrom,
    this.worktreePath,
    this.branch,
    this.baseBranch,
    this.repoRemote,
    this.headSha,
    this.title,
    this.tags = const [],
    this.prUrl,
    this.prStatus,
    this.tokenCount,
    this.cost,
    this.summary,
  });

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'id': id,
        'cwd': cwd,
        if (projectPath != null) 'project_path': projectPath,
        'model': model,
        'provider': provider,
        'start_time': startTime.toUtc().toIso8601String(),
        if (endTime != null) 'end_time': endTime!.toUtc().toIso8601String(),
        if (forkedFrom != null) 'forked_from': forkedFrom,
        if (worktreePath != null) 'worktree_path': worktreePath,
        if (branch != null) 'branch': branch,
        if (baseBranch != null) 'base_branch': baseBranch,
        if (repoRemote != null) 'repo_remote': repoRemote,
        if (headSha != null) 'head_sha': headSha,
        if (title != null) 'title': title,
        if (tags.isNotEmpty) 'tags': tags,
        if (prUrl != null) 'pr_url': prUrl,
        if (prStatus != null) 'pr_status': prStatus,
        if (tokenCount != null) 'token_count': tokenCount,
        if (cost != null) 'cost': cost,
        if (summary != null) 'summary': summary,
      };

  factory SessionMeta.fromJson(Map<String, dynamic> json) => SessionMeta(
        schemaVersion: json['schema_version'] as int? ?? 1,
        id: json['id'] as String,
        cwd: json['cwd'] as String? ?? '',
        projectPath: json['project_path'] as String?,
        model: json['model'] as String? ?? 'unknown',
        provider: json['provider'] as String? ?? 'unknown',
        startTime: DateTime.parse(json['start_time'] as String),
        endTime: json['end_time'] != null
            ? DateTime.parse(json['end_time'] as String)
            : null,
        forkedFrom: json['forked_from'] as String?,
        worktreePath: json['worktree_path'] as String?,
        branch: json['branch'] as String?,
        baseBranch: json['base_branch'] as String?,
        repoRemote: json['repo_remote'] as String?,
        headSha: json['head_sha'] as String?,
        title: json['title'] as String?,
        tags: (json['tags'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        prUrl: json['pr_url'] as String?,
        prStatus: json['pr_status'] as String?,
        tokenCount: json['token_count'] as int?,
        cost: (json['cost'] as num?)?.toDouble(),
        summary: json['summary'] as String?,
      );
}

/// Persistent storage for a single session's metadata and conversation log.
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

  void setTitle(String title) {
    meta.title = title;
    _writeMeta();
  }

  /// Writes the current metadata to disk.
  void updateMeta() => _writeMeta();

  /// Appends a timestamped event record to the conversation log.
  void logEvent(String type, Map<String, dynamic> data) {
    final record = {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'type': type,
      ...data,
    };
    _conversationFile.writeAsStringSync(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
    );
  }

  /// Closes this session, recording the end time.
  Future<void> close() async {
    meta.endTime = DateTime.now().toUtc();
    _writeMeta();
  }

  /// Lists all saved sessions in [sessionsDir], sorted newest first.
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
        sessions.add(SessionMeta.fromJson(json));
      } catch (_) {}
    }

    sessions.sort((a, b) => b.startTime.compareTo(a.startTime));
    return sessions;
  }

  /// Loads the conversation log for a session from its [sessionDir].
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
